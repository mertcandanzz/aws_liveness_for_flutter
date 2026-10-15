import { App } from 'aws-cdk-lib';
import { Match, Template } from 'aws-cdk-lib/assertions';
import { beforeAll, describe, expect, it } from 'vitest';
import { LivenessBackendStack } from '../infra/stack.js';

const DIGEST = 'f'.repeat(64);

function synth(props: Partial<ConstructorParameters<typeof LivenessBackendStack>[2]> = {}): Template {
  // Skip esbuild bundling: the template, not the bundle, is under test.
  const app = new App({ context: { 'aws:cdk:bundling-stacks': [] } });
  const stack = new LivenessBackendStack(app, 'Test', { apiTokenSha256: [DIGEST], ...props });
  return Template.fromStack(stack);
}

type Statement = { Action: string | string[]; Resource: unknown; Effect: string };

/** Actions granted to the role whose logical id starts with [rolePrefix]. */
function actionsOf(template: Template, rolePrefix: string): string[] {
  const policies = template.findResources('AWS::IAM::Policy');
  const actions: string[] = [];
  for (const policy of Object.values(policies) as { Properties: { Roles: { Ref: string }[]; PolicyDocument: { Statement: Statement[] } } }[]) {
    if (!policy.Properties.Roles.some((r) => r.Ref.startsWith(rolePrefix))) continue;
    for (const s of policy.Properties.PolicyDocument.Statement) {
      actions.push(...(Array.isArray(s.Action) ? s.Action : [s.Action]));
    }
  }
  return actions.sort();
}

describe('LivenessBackendStack', () => {
  let template: Template;
  beforeAll(() => {
    template = synth();
  });

  it('gives each function only the actions it calls', () => {
    expect(actionsOf(template, 'CreateSessionRole')).toEqual(['dynamodb:PutItem', 'rekognition:CreateFaceLivenessSession']);
    expect(actionsOf(template, 'CredentialsRole')).toEqual(['dynamodb:GetItem', 'sts:AssumeRole']);
    expect(actionsOf(template, 'GetResultRole')).toEqual([
      'dynamodb:GetItem',
      'dynamodb:UpdateItem',
      'rekognition:GetFaceLivenessSessionResults',
    ]);
    expect(actionsOf(template, 'AuthorizerRole')).toEqual([]);
  });

  it('lets the client role do nothing but stream a liveness check', () => {
    expect(actionsOf(template, 'LivenessClientRole')).toEqual(['rekognition:StartFaceLivenessSession']);
  });

  it('lets only the credentials function assume the client role', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      Description: Match.stringLikeRegexp('only rekognition:StartFaceLivenessSession'),
      AssumeRolePolicyDocument: {
        Statement: [
          {
            Action: 'sts:AssumeRole',
            Effect: 'Allow',
            Principal: { AWS: { 'Fn::GetAtt': [Match.stringLikeRegexp('^CredentialsRole'), 'Arn'] } },
          },
        ],
      },
    });
  });

  it('scopes the credentials function to that one role', () => {
    template.hasResourceProperties('AWS::IAM::Policy', {
      Roles: [{ Ref: Match.stringLikeRegexp('^CredentialsRole') }],
      PolicyDocument: {
        Statement: Match.arrayWith([
          Match.objectLike({
            Action: 'sts:AssumeRole',
            Resource: { 'Fn::GetAtt': [Match.stringLikeRegexp('^LivenessClientRole'), 'Arn'] },
          }),
        ]),
      },
    });
  });

  it('expires session bindings with a TTL attribute', () => {
    template.hasResourceProperties('AWS::DynamoDB::GlobalTable', {
      TimeToLiveSpecification: { AttributeName: 'expiresAt', Enabled: true },
      KeySchema: [{ AttributeName: 'sessionId', KeyType: 'HASH' }],
    });
  });

  it('throttles the default stage', () => {
    template.hasResourceProperties('AWS::ApiGatewayV2::Stage', {
      StageName: '$default',
      DefaultRouteSettings: { ThrottlingRateLimit: 10, ThrottlingBurstLimit: 20 },
    });
  });

  it('protects every route with the Lambda authorizer', () => {
    const routes = template.findResources('AWS::ApiGatewayV2::Route');
    expect(Object.keys(routes)).toHaveLength(3);
    for (const route of Object.values(routes) as { Properties: { AuthorizationType: string } }[]) {
      expect(route.Properties.AuthorizationType).toBe('CUSTOM');
    }
    template.hasResourceProperties('AWS::ApiGatewayV2::Authorizer', {
      AuthorizerType: 'REQUEST',
      EnableSimpleResponses: true,
      IdentitySource: ['$request.header.Authorization'],
    });
  });

  it('passes only token digests and safe defaults to the functions', () => {
    template.hasResourceProperties('AWS::Lambda::Function', {
      Environment: { Variables: { API_TOKEN_SHA256: DIGEST } },
    });
    template.hasResourceProperties('AWS::Lambda::Function', {
      Environment: {
        Variables: Match.objectLike({
          LIVENESS_CHALLENGE: 'FaceMovementChallenge',
          LIVENESS_ALLOW_CLIENT_CHALLENGE: 'false',
          LIVENESS_AUDIT_IMAGES_LIMIT: '0',
        }),
      },
    });
    template.hasResourceProperties('AWS::Lambda::Function', {
      Environment: { Variables: Match.objectLike({ LIVENESS_CONFIDENCE_THRESHOLD: '80' }) },
    });
  });

  it('adds s3:PutObject on the output prefix only when configured', () => {
    const withOutput = synth({ outputBucketName: 'audit-bucket', outputKeyPrefix: 'liveness/' });

    expect(actionsOf(withOutput, 'CreateSessionRole')).toContain('s3:PutObject');
    withOutput.hasResourceProperties('AWS::IAM::Policy', {
      PolicyDocument: {
        Statement: Match.arrayWith([
          Match.objectLike({
            Action: 's3:PutObject',
            Resource: { 'Fn::Join': ['', ['arn:', { Ref: 'AWS::Partition' }, ':s3:::audit-bucket/liveness/*']] },
          }),
        ]),
      },
    });
  });

  it('rejects plain tokens in place of digests', () => {
    expect(() => synth({ apiTokenSha256: ['my-plain-token'] })).toThrow(/SHA-256/);
  });
});
