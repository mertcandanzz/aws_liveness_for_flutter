import { App } from 'aws-cdk-lib';
import { LivenessBackendStack, type ChallengeType } from './stack.js';

// Configuration comes from CDK context (-c key=value or cdk.json), never from
// committed secrets. apiTokenSha256 is a comma-separated list of SHA-256 hex
// digests of your bearer tokens, not the tokens themselves.
const app = new App();
const context = (key: string): string | undefined => {
  const value: unknown = app.node.tryGetContext(key);
  return typeof value === 'string' && value.trim() !== '' ? value.trim() : undefined;
};
const number = (key: string): number | undefined => {
  const value = context(key);
  return value === undefined ? undefined : Number(value);
};

const apiTokenSha256 = context('apiTokenSha256');
if (!apiTokenSha256) {
  throw new Error('Pass -c apiTokenSha256=<sha256 hex of your token>[,<more>] (see README).');
}

new LivenessBackendStack(app, context('stackName') ?? 'AwsLivenessBackend', {
  env: { account: process.env.CDK_DEFAULT_ACCOUNT, region: process.env.CDK_DEFAULT_REGION },
  apiTokenSha256: apiTokenSha256.split(',').map((d) => d.trim()),
  challenge: context('challenge') as ChallengeType | undefined,
  allowClientChallenge: context('allowClientChallenge') === 'true',
  auditImagesLimit: number('auditImagesLimit'),
  outputBucketName: context('outputBucketName'),
  outputKeyPrefix: context('outputKeyPrefix'),
  confidenceThreshold: number('confidenceThreshold'),
  throttle:
    context('rateLimit') && context('burstLimit')
      ? { rateLimit: Number(context('rateLimit')), burstLimit: Number(context('burstLimit')) }
      : undefined,
});
