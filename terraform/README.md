# Terraform

These Terraform files will create the setup as shown in the architecture.

## Prerequisites

- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) with credential configured.
- [terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)

## Setup

Change working directory to `terraform/`. Use `terraform init` only for the first time.

After editing `main.tf`, format the file:

```sh
terraform fmt
```

Review the changes compared to the current setup:

```sh
terraform plan
```

Apply/deploy the changes if everything looks correct:

```sh
terraform apply
```

To tear down everything:

```sh
terraform plan -destroy # Review carefully
terraform destroy
```

Most editing happens in `main.tf` and rarely `variables.tf`. `outputs.tf` shows the output after applying the changes.
