import {
  ConditionalCheckFailedException,
  GetItemCommand,
  PutItemCommand,
  UpdateItemCommand,
  type DynamoDBClient,
} from '@aws-sdk/client-dynamodb';

/** Sessions expire ~3 minutes after creation; results are read shortly after. */
export const SESSION_TTL_SECONDS = 600;

export type SessionState = 'missing' | 'owned' | 'consumed';

/**
 * Binds sessions to callers in DynamoDB, so every Lambda invocation sees the
 * same binding. A session's result can be consumed once.
 *
 * Items: `sessionId` (key), `owner`, `createdAt`, `expiresAt` (TTL) and
 * `consumedAt` once the final result was handed out. DynamoDB deletes expired
 * items lazily, so `expiresAt` is also checked here.
 */
export class SessionTable {
  constructor(
    private readonly db: Pick<DynamoDBClient, 'send'>,
    private readonly table: string,
    private readonly nowSeconds: () => number = () => Math.floor(Date.now() / 1000),
  ) {}

  async bind(sessionId: string, owner: string): Promise<void> {
    const now = this.nowSeconds();
    await this.db.send(
      new PutItemCommand({
        TableName: this.table,
        Item: {
          sessionId: { S: sessionId },
          owner: { S: owner },
          createdAt: { N: String(now) },
          expiresAt: { N: String(now + SESSION_TTL_SECONDS) },
        },
        ConditionExpression: 'attribute_not_exists(sessionId)',
      }),
    );
  }

  /** `owned` only for the creator, before expiry and before the result was consumed. */
  async state(sessionId: string, caller: string): Promise<SessionState> {
    const { Item: item } = await this.db.send(
      new GetItemCommand({ TableName: this.table, Key: { sessionId: { S: sessionId } }, ConsistentRead: true }),
    );
    if (!item || item.owner?.S !== caller) return 'missing';
    if (Number(item.expiresAt?.N ?? 0) <= this.nowSeconds()) return 'missing';
    return item.consumedAt ? 'consumed' : 'owned';
  }

  /** Marks the final result as handed out. False if another request won the race. */
  async consume(sessionId: string, caller: string): Promise<boolean> {
    try {
      await this.db.send(
        new UpdateItemCommand({
          TableName: this.table,
          Key: { sessionId: { S: sessionId } },
          UpdateExpression: 'SET consumedAt = :now',
          ConditionExpression: '#owner = :caller AND attribute_not_exists(consumedAt)',
          ExpressionAttributeNames: { '#owner': 'owner' },
          ExpressionAttributeValues: { ':now': { N: String(this.nowSeconds()) }, ':caller': { S: caller } },
        }),
      );
      return true;
    } catch (error) {
      if (error instanceof ConditionalCheckFailedException) return false;
      throw error;
    }
  }
}
