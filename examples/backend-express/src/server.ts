import { RekognitionClient } from '@aws-sdk/client-rekognition';
import { STSClient } from '@aws-sdk/client-sts';
import { createApp } from './app.js';
import { ConfigError, loadConfig } from './config.js';

// AWS credentials for this server come from the standard provider chain
// (environment, shared profile, instance or task role). Never from the app.
let config;
try {
  config = loadConfig(process.env);
} catch (error) {
  if (error instanceof ConfigError) {
    console.error(`Configuration error: ${error.message}`);
    process.exit(1);
  }
  throw error;
}

const app = createApp({
  config,
  rekognition: new RekognitionClient({ region: config.region }),
  sts: new STSClient({ region: config.region }),
  log: (entry) => console.info(JSON.stringify(entry)),
});

app.listen(config.port, () => {
  console.info(JSON.stringify({ event: 'listening', port: config.port, region: config.region }));
});
