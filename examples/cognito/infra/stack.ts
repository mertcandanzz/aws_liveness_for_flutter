import { CfnOutput, Duration, RemovalPolicy, Stack, type StackProps } from 'aws-cdk-lib';
import { AccountRecovery, Mfa, UserPool, UserPoolClient } from 'aws-cdk-lib/aws-cognito';
import { IdentityPool, UserPoolAuthenticationProvider } from 'aws-cdk-lib/aws-cognito-identitypool';
import { PolicyStatement } from 'aws-cdk-lib/aws-iam';
import type { Construct } from 'constructs';

export interface LivenessCognitoProps extends StackProps {
  /** Let anyone create an account. Off by default: an admin invites users. */
  selfSignUp?: boolean;
}

/**
 * A user pool for sign-in and an identity pool that exchanges the user's
 * tokens for AWS credentials. The authenticated role can only stream a Face
 * Liveness check; guests get nothing.
 *
 * Creating sessions and reading results stays on your backend (for example
 * backend-lambda behind a JWT authorizer on this user pool).
 */
export class LivenessCognitoStack extends Stack {
  constructor(scope: Construct, id: string, props: LivenessCognitoProps = {}) {
    super(scope, id, props);

    const userPool = new UserPool(this, 'Users', {
      selfSignUpEnabled: props.selfSignUp ?? false,
      signInAliases: { email: true },
      autoVerify: { email: true },
      accountRecovery: AccountRecovery.EMAIL_ONLY,
      mfa: Mfa.OPTIONAL,
      mfaSecondFactor: { otp: true, sms: false },
      passwordPolicy: {
        minLength: 12,
        requireLowercase: true,
        requireUppercase: true,
        requireDigits: true,
        requireSymbols: false,
      },
      removalPolicy: RemovalPolicy.DESTROY,
    });

    const client = new UserPoolClient(this, 'AppClient', {
      userPool,
      generateSecret: false,
      authFlows: { userSrp: true },
      preventUserExistenceErrors: true,
      accessTokenValidity: Duration.minutes(60),
      idTokenValidity: Duration.minutes(60),
      refreshTokenValidity: Duration.days(30),
    });

    const identityPool = new IdentityPool(this, 'Identities', {
      allowUnauthenticatedIdentities: false,
      authenticationProviders: {
        userPools: [new UserPoolAuthenticationProvider({ userPool, userPoolClient: client })],
      },
    });

    // The only permission signed-in users receive.
    identityPool.authenticatedRole.addToPrincipalPolicy(
      new PolicyStatement({ actions: ['rekognition:StartFaceLivenessSession'], resources: ['*'] }),
    );

    new CfnOutput(this, 'UserPoolId', { value: userPool.userPoolId });
    new CfnOutput(this, 'UserPoolClientId', { value: client.userPoolClientId });
    new CfnOutput(this, 'IdentityPoolId', { value: identityPool.identityPoolId });
    new CfnOutput(this, 'Region', { value: this.region });
  }
}
