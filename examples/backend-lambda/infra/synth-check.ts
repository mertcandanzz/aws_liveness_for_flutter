import { App } from 'aws-cdk-lib';
import { LivenessBackendStack } from './stack.js';

// `npm run synth`: synthesizes the stack into cdk.out without the CDK CLI, so
// no AWS credentials are read and no account is looked up. The stack is
// environment-agnostic and uses a placeholder digest that matches no token.
const app = new App({ outdir: 'cdk.out' });
new LivenessBackendStack(app, 'AwsLivenessBackend', { apiTokenSha256: ['0'.repeat(64)] });
app.synth();
