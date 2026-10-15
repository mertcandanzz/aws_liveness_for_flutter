import { App } from 'aws-cdk-lib';
import { LivenessCognitoStack } from './stack.js';

const app = new App();
const stackName: unknown = app.node.tryGetContext('stackName');

new LivenessCognitoStack(app, typeof stackName === 'string' ? stackName : 'AwsLivenessCognito', {
  env: { account: process.env.CDK_DEFAULT_ACCOUNT, region: process.env.CDK_DEFAULT_REGION },
  selfSignUp: app.node.tryGetContext('selfSignUp') === 'true',
});
