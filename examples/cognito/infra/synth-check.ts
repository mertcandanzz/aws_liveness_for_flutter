import { App } from 'aws-cdk-lib';
import { LivenessCognitoStack } from './stack.js';

// `npm run synth`: renders the template into cdk.out without the CDK CLI, so
// no AWS credentials are read and no account is looked up.
const app = new App({ outdir: 'cdk.out' });
new LivenessCognitoStack(app, 'AwsLivenessCognito');
app.synth();
