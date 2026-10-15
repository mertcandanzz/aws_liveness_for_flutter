import { join } from 'node:path';
import { CfnOutput, Duration, RemovalPolicy, Stack, type StackProps } from 'aws-cdk-lib';
import { HttpApi, HttpMethod, HttpStage } from 'aws-cdk-lib/aws-apigatewayv2';
import { HttpLambdaAuthorizer, HttpLambdaResponseType } from 'aws-cdk-lib/aws-apigatewayv2-authorizers';
import { HttpLambdaIntegration } from 'aws-cdk-lib/aws-apigatewayv2-integrations';
import { AttributeType, Billing, TableV2 } from 'aws-cdk-lib/aws-dynamodb';
import { ManagedPolicy, PolicyStatement, Role, ServicePrincipal } from 'aws-cdk-lib/aws-iam';
import { Architecture, Runtime } from 'aws-cdk-lib/aws-lambda';
import { NodejsFunction } from 'aws-cdk-lib/aws-lambda-nodejs';
import { LogGroup, RetentionDays } from 'aws-cdk-lib/aws-logs';
import type { Construct } from 'constructs';

export type ChallengeType = 'FaceMovementChallenge' | 'FaceMovementAndLightChallenge';

export interface LivenessBackendProps extends StackProps {
  /** SHA-256 hex digests of the accepted bearer tokens; never the tokens. */
  apiTokenSha256: readonly string[];
  challenge?: ChallengeType;
  /** Let callers pick the challenge. Demo only; off by default. */
  allowClientChallenge?: boolean;
  /** 0-4 audit images; default 0. */
  auditImagesLimit?: number;
  /** Optional S3 output for reference and audit images. */
  outputBucketName?: string;
  outputKeyPrefix?: string;
  /** Minimum confidence (0-100) for isLive; default 80. */
  confidenceThreshold?: number;
  /** Stage-wide request rate limit; default 10 requests/s, burst 20. */
  throttle?: { rateLimit: number; burstLimit: number };
}

const HANDLERS = join(import.meta.dirname, '..', 'src', 'handlers');

/**
 * HTTP API with a Lambda authorizer and three functions. Every function has
 * its own role with only the actions it calls.
 */
export class LivenessBackendStack extends Stack {
  constructor(scope: Construct, id: string, props: LivenessBackendProps) {
    super(scope, id, props);

    if (props.apiTokenSha256.length === 0 || props.apiTokenSha256.some((d) => !/^[0-9a-f]{64}$/i.test(d))) {
      throw new Error('apiTokenSha256 must contain SHA-256 hex digests');
    }

    const table = new TableV2(this, 'Sessions', {
      partitionKey: { name: 'sessionId', type: AttributeType.STRING },
      billing: Billing.onDemand(),
      timeToLiveAttribute: 'expiresAt',
      removalPolicy: RemovalPolicy.DESTROY,
    });

    const fn = (name: string, entry: string, environment: Record<string, string>) => {
      const role = new Role(this, `${name}Role`, {
        assumedBy: new ServicePrincipal('lambda.amazonaws.com'),
        managedPolicies: [ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')],
      });
      const fn = new NodejsFunction(this, name, {
        entry: join(HANDLERS, entry),
        handler: 'handler',
        runtime: Runtime.NODEJS_22_X,
        architecture: Architecture.ARM_64,
        memorySize: 256,
        timeout: Duration.seconds(10),
        role,
        environment,
        logGroup: new LogGroup(this, `${name}Logs`, {
          retention: RetentionDays.ONE_WEEK,
          removalPolicy: RemovalPolicy.DESTROY,
        }),
        bundling: { minify: true, sourceMap: false, target: 'node22' },
      });
      return { fn, role };
    };

    const sessionsEnv = { SESSIONS_TABLE: table.tableName };

    // Create session: CreateFaceLivenessSession, PutItem (and S3 output if set).
    const create = fn('CreateSession', 'createSession.ts', {
      ...sessionsEnv,
      LIVENESS_CHALLENGE: props.challenge ?? 'FaceMovementChallenge',
      LIVENESS_ALLOW_CLIENT_CHALLENGE: String(props.allowClientChallenge ?? false),
      LIVENESS_AUDIT_IMAGES_LIMIT: String(props.auditImagesLimit ?? 0),
      ...(props.outputBucketName ? { LIVENESS_OUTPUT_S3_BUCKET: props.outputBucketName } : {}),
      ...(props.outputKeyPrefix ? { LIVENESS_OUTPUT_S3_KEY_PREFIX: props.outputKeyPrefix } : {}),
    });
    create.role.addToPolicy(
      new PolicyStatement({ actions: ['rekognition:CreateFaceLivenessSession'], resources: ['*'] }),
    );
    table.grant(create.role, 'dynamodb:PutItem');
    if (props.outputBucketName) {
      create.role.addToPolicy(
        new PolicyStatement({
          actions: ['s3:PutObject'],
          resources: [`arn:${this.partition}:s3:::${props.outputBucketName}/${props.outputKeyPrefix ?? ''}*`],
        }),
      );
    }

    // Credentials: GetItem, and AssumeRole on the liveness client role only.
    const credentialsRole = new Role(this, 'CredentialsRole', {
      assumedBy: new ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')],
    });
    const clientRole = new Role(this, 'LivenessClientRole', {
      assumedBy: credentialsRole,
      description: 'Assumed for app credentials; allows only rekognition:StartFaceLivenessSession.',
      maxSessionDuration: Duration.hours(1),
    });
    clientRole.addToPolicy(
      new PolicyStatement({ actions: ['rekognition:StartFaceLivenessSession'], resources: ['*'] }),
    );
    const credentials = new NodejsFunction(this, 'Credentials', {
      entry: join(HANDLERS, 'credentials.ts'),
      handler: 'handler',
      runtime: Runtime.NODEJS_22_X,
      architecture: Architecture.ARM_64,
      memorySize: 256,
      timeout: Duration.seconds(10),
      role: credentialsRole,
      environment: { ...sessionsEnv, LIVENESS_CREDENTIALS_ROLE_ARN: clientRole.roleArn },
      logGroup: new LogGroup(this, 'CredentialsLogs', {
        retention: RetentionDays.ONE_WEEK,
        removalPolicy: RemovalPolicy.DESTROY,
      }),
      bundling: { minify: true, sourceMap: false, target: 'node22' },
    });
    table.grant(credentialsRole, 'dynamodb:GetItem');
    clientRole.grantAssumeRole(credentialsRole);

    // Results: GetFaceLivenessSessionResults, GetItem and UpdateItem (consume once).
    const result = fn('GetResult', 'getResult.ts', {
      ...sessionsEnv,
      LIVENESS_CONFIDENCE_THRESHOLD: String(props.confidenceThreshold ?? 80),
    });
    result.role.addToPolicy(
      new PolicyStatement({ actions: ['rekognition:GetFaceLivenessSessionResults'], resources: ['*'] }),
    );
    table.grant(result.role, 'dynamodb:GetItem', 'dynamodb:UpdateItem');

    // Authorizer: no AWS permissions beyond its logs.
    const authorizerFn = fn('Authorizer', 'authorizer.ts', {
      API_TOKEN_SHA256: props.apiTokenSha256.join(','),
    });
    const authorizer = new HttpLambdaAuthorizer('BearerAuthorizer', authorizerFn.fn, {
      responseTypes: [HttpLambdaResponseType.SIMPLE],
      identitySource: ['$request.header.Authorization'],
      resultsCacheTtl: Duration.minutes(5),
    });

    const api = new HttpApi(this, 'Api', {
      createDefaultStage: false,
      defaultAuthorizer: authorizer,
      description: 'aws_liveness_for_flutter example backend',
    });
    api.addRoutes({
      path: '/liveness/sessions',
      methods: [HttpMethod.POST],
      integration: new HttpLambdaIntegration('CreateSessionIntegration', create.fn),
    });
    api.addRoutes({
      path: '/liveness/credentials',
      methods: [HttpMethod.POST],
      integration: new HttpLambdaIntegration('CredentialsIntegration', credentials),
    });
    api.addRoutes({
      path: '/liveness/sessions/{sessionId}/result',
      methods: [HttpMethod.GET],
      integration: new HttpLambdaIntegration('GetResultIntegration', result.fn),
    });

    const stage = new HttpStage(this, 'DefaultStage', {
      httpApi: api,
      stageName: '$default',
      autoDeploy: true,
      throttle: props.throttle ?? { rateLimit: 10, burstLimit: 20 },
    });

    new CfnOutput(this, 'ApiUrl', { value: stage.url });
    new CfnOutput(this, 'SessionsTableName', { value: table.tableName });
    new CfnOutput(this, 'LivenessClientRoleArn', { value: clientRole.roleArn });
  }
}
