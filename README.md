# fan-platform — Day 3: CI/CD with GitHub Actions + OIDC

Practice project modeled on a K-entertainment fan platform (traffic spikes on
ticket opens / album drops). Day 3 sets up the pipeline first, so every later
piece of infra (VPC, ALB, ECS, RDS...) goes through pull requests.

```
bootstrap/                     run once from your laptop
  main.tf                      state bucket, GitHub OIDC provider, plan + apply roles
infra/
  main.tf                      real infra lives here (starts with one S3 bucket)
.github/workflows/
  terraform.yml                PR -> plan (read-only role), main -> apply
```

## How it works

| Event            | AWS role assumed        | What runs                          |
|------------------|-------------------------|------------------------------------|
| Pull request     | `github-actions-plan`   | fmt, validate, plan (summary)      |
| Push to `main`   | `github-actions-apply`  | fmt, validate, plan, **apply**     |

No AWS keys are stored in GitHub. GitHub issues a short-lived OIDC token; AWS
only accepts it if the `sub` claim matches your repo *and* the event
(`pull_request` or `ref:refs/heads/main`).

## Setup (about 15 minutes)

1. **Create the GitHub repo** (e.g. `yourname/fan-platform`) and push this folder.

2. **Bootstrap AWS** from your laptop with admin credentials:
   ```bash
   cd bootstrap
   terraform init
   terraform apply -var="github_repo=yourname/fan-platform"
   ```
   If your account already has the GitHub OIDC provider, import it first:
   ```bash
   terraform import aws_iam_openid_connect_provider.github \
     arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com
   ```

3. **Add repo variables** (Settings → Secrets and variables → Actions → *Variables*,
   not secrets — these values aren't sensitive):
   - `TF_STATE_BUCKET` = `state_bucket` output
   - `AWS_PLAN_ROLE_ARN` = `plan_role_arn` output
   - `AWS_APPLY_ROLE_ARN` = `apply_role_arn` output

4. **Protect `main`**: require a pull request and a passing `terraform` check.

5. **Test it**: create a branch, add a tag to the bucket in `infra/main.tf`,
   open a PR → read the plan in the job summary → merge → watch apply run.

## Exercises (do these, they're interview material)

- [ ] Break it on purpose: change the trust policy `sub` to a wrong branch and
      read the error. Learn what `Not authorized to perform sts:AssumeRoleWithWebIdentity` means.
- [ ] On a PR, try to `apply` with the plan role — confirm it's denied.
- [ ] Add a `GitHub Environment` called `production` with a required reviewer,
      and attach the apply job to it (manual approval gate).
- [ ] Post the plan as a PR comment (hint: `actions/github-script` + `pull-requests: write`).
- [ ] Add `tflint` and `checkov` (or `trivy config`) steps for security scanning.
- [ ] Replace `AdministratorAccess` on the apply role with scoped policies.
      Write an **ADR** explaining the trade-off.

## Cleanup

```bash
cd infra && terraform destroy          # or via a PR that removes resources
cd ../bootstrap && terraform destroy   # empty the state bucket first
```
