import json
import boto3

def on_default(event, context):
    print(context)
    print(event)
    raise Exception("Default handler triggered.")
