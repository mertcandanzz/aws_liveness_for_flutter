import { App } from 'aws-cdk-lib';
import { Match, Template } from 'aws-cdk-lib/assertions';
import { beforeAll, describe, expect, it } from 'vitest';
import { LivenessCognitoStack } from '../infra/stack.js';

type Statement = { Action: string | string[] };
type PolicyResource = { Properties: { Roles: { Ref: string }[]; PolicyDocument: { Statement: Statement[] } } };
type RoleResource = {
  Properties: {
    AssumeRolePolicyDocument: {
      Statement: { Condition?: Record<string, Record<string, unknown>> }[];
    };
    ManagedPolicyArns?: unknown[];
    Policies?: unknown[];
  };
};

describe('LivenessCognitoStack', () => {
  let template: Template;
  beforeAll(() => {
    template = Template.fromStack(new LivenessCognitoStack(new App(), 'Test'));
  });

  /** Logical ids of the identity pool roles by `amr` value. */
  function roleIds(): { authenticated: string; unauthenticated: string } {
    const roles = template.findResources('AWS::IAM::Role') as Record<string, RoleResource>;
    const ids: Record<string, string> = {};
    for (const [id, role] of Object.entries(roles)) {
      const condition = role.Properties.AssumeRolePolicyDocument.Statement[0]?.Condition ?? {};
      const amr = condition['ForAnyValue:StringLike']?.['cognito-identity.amazonaws.com:amr'];
      if (typeof amr === 'string') ids[amr] = id;
    }
    return { authenticated: ids.authenticated ?? '', unauthenticated: ids.unauthenticated ?? '' };
  }

  function actionsOf(roleId: string): string[] {
    const policies = template.findResources('AWS::IAM::Policy') as Record<string, PolicyResource>;
    return Object.values(policies)
      .filter((p) => p.Properties.Roles.some((r) => r.Ref === roleId))
      .flatMap((p) => p.Properties.PolicyDocument.Statement.flatMap((s) => (Array.isArray(s.Action) ? s.Action : [s.Action])));
  }

  it('gives signed-in users only StartFaceLivenessSession', () => {
    const { authenticated } = roleIds();

    expect(authenticated).not.toBe('');
    expect(actionsOf(authenticated)).toEqual(['rekognition:StartFaceLivenessSession']);
    const role = (template.findResources('AWS::IAM::Role') as Record<string, RoleResource>)[authenticated];
    expect(role?.Properties.ManagedPolicyArns ?? []).toEqual([]);
    expect(role?.Properties.Policies ?? []).toEqual([]);
  });

  it('never grants session creation or result reads to the app', () => {
    const all = JSON.stringify(template.toJSON());

    expect(all).not.toContain('CreateFaceLivenessSession');
    expect(all).not.toContain('GetFaceLivenessSessionResults');
  });

  it('gives guests nothing and disables guest identities', () => {
    const { unauthenticated } = roleIds();

    expect(actionsOf(unauthenticated)).toEqual([]);
    template.hasResourceProperties('AWS::Cognito::IdentityPool', {
      AllowUnauthenticatedIdentities: false,
    });
  });

  it('trusts the authenticated role only for this identity pool and authenticated users', () => {
    const { authenticated } = roleIds();
    const role = (template.findResources('AWS::IAM::Role') as Record<string, RoleResource>)[authenticated];
    const condition = role?.Properties.AssumeRolePolicyDocument.Statement[0]?.Condition;

    const [poolId] = Object.keys(template.findResources('AWS::Cognito::IdentityPool'));
    expect(condition?.StringEquals?.['cognito-identity.amazonaws.com:aud']).toEqual({ Ref: poolId });
    expect(condition?.['ForAnyValue:StringLike']?.['cognito-identity.amazonaws.com:amr']).toBe('authenticated');
  });

  it('uses a public app client with SRP and no secret', () => {
    template.hasResourceProperties('AWS::Cognito::UserPoolClient', {
      GenerateSecret: false,
      ExplicitAuthFlows: Match.arrayWith(['ALLOW_USER_SRP_AUTH']),
      PreventUserExistenceErrors: 'ENABLED',
    });
  });

  it('keeps self sign-up off by default and enforces a password policy', () => {
    template.hasResourceProperties('AWS::Cognito::UserPool', {
      AdminCreateUserConfig: { AllowAdminCreateUserOnly: true },
      Policies: { PasswordPolicy: Match.objectLike({ MinimumLength: 12 }) },
    });
  });
});
