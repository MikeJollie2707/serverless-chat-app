import json
import boto3
import datetime as dt
import os

def on_message(event, context):
    dynamodb = boto3.resource('dynamodb')
    connectionTable = dynamodb.Table(os.getenv("connectionTableName"))
    messageTable = dynamodb.Table(os.getenv("messageTableName"))
    sns = boto3.resource('sns')
    snsTopic = sns.Topic(os.getenv("messageTopicARN"))

    response = connectionTable.get_item(
        Key={
            'connectionId': event['requestContext']['connectionId']
        })
    # TODO: { "connectionId": "...", "userID": "...", "region": "region-str" }
    item = response.get('Item')
    if not item:
        return {
            'statusCode': 400,
            'body': json.dumps('Connection not found')
        }
    
    body = json.loads(event["body"])
    messageID = dt.datetime.now().timestamp()

    try:
        messageTable.put_item(
            Item={
                'messageID': str(messageID),
                'message': body["message"],
            }
        )
    except:
        return {
            'statusCode': 500,
            'body': json.dumps('Message not saved')
        }
    
    snsTopic.publish(
        Message=json.dumps({
            'messageID': str(messageID),
            'message': body["message"],
            'author': "Some Dude",
        }),
    )
    return {
        'statusCode': 200,
    }