To deploy this function to Lambda:

```sh
cd lambda/authorizer
mkdir deps
```

Install dependencies into the folder:

```sh
python3 -m pip install --target deps/ boto3 'pyjwt[crypto]'
```

Zip it once:

```sh
cd deps
zip -r ../package.zip .
```

Zip it another time:

```sh
cd ..
zip package.zip authorizer.py
```

Now you can upload `package.zip` to AWS Lambda.

You need to edit the Lambda runtime to be `authorizer.authorizer`. The version needs to match with your local Python version (up to minor version according to semver). Don't forget to set environment variables.
