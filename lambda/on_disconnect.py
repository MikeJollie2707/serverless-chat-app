import json
import boto3
import os

def on_disconnect(event, context):
    dynamodb = boto3.resource('dynamodb')
    connectionTable = dynamodb.Table(os.getenv("connectionTableName"))

    try:
        connectionTable.delete_item(
            Key={
                'connectionId': event['requestContext']['connectionId']
            }
        )
    except Exception as e:
        print(e)
        return {
            'statusCode': 500,
        }
    
    return {
        'statusCode': 200,
    }