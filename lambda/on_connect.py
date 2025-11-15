import json
import boto3
import os

def on_connect(event, context):
    print(event)
    dynamodb = boto3.resource("dynamodb")
    connectionTable = dynamodb.Table(os.getenv("connectionTableName"))

    try:
        connectionTable.put_item(
            Item={
                "connectionId": event["requestContext"]["connectionId"]
            }
        )
    except Exception as err:
        print(err)
        return {
            'statusCode': 500,
        }
    
    return {
        'statusCode': 200,
    }