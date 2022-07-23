#!/usr/bin/env python
# coding=utf8

"""index.py:
     Lambda to start and stop ECS task on-fly. The way to scale-to-zero application with an ELB
     Also call green-lambda
"""

__author__ = "Mathieu GOULIN"
__copyright__ = "Copyright 2022, Kapable.info"
__credits__ = ["Mathieu GOULIN"]
__license__ = "GPL"
__version__ = "1.0.0"
__maintainer__ = "Mathieu GOULIN"
__email__ = "mathieu.goulin@gadz.org"
__status__ = "Production"

###############################################################################
# Imports & common declaration
###############################################################################
import boto3
import os
import json
import time

ecs = boto3.client('ecs')
alb = boto3.client('elbv2')

ecs_cluster = os.environ['ECS_CLUSTER_NAME']
ecs_service = os.environ['ECS_SERVICE_NAME']
rule_enable_priority = int(os.environ['RULE_PRIORITY'])
rule_disable_priority = 50 + rule_enable_priority
rule_arn = os.environ['RULE_ARN']

###############################################################################
# Function to stop ecs task : set desiredcount=0 and un-priorize ALB rules
###############################################################################
def stop(event, context):
    response = ecs.update_service(
        cluster=ecs_cluster,
        service=ecs_service,
        desiredCount=0,
    )
    response = alb.set_rule_priorities(
        RulePriorities=[
            {
                'Priority': rule_disable_priority,
                'RuleArn': rule_arn,
            },
        ],
    )

    return {}

###############################################################################
# Function to start ecs task
###############################################################################
def start(event, context):
    response = ecs.update_service(
        cluster=ecs_cluster,
        service=ecs_service,
        desiredCount=1,
    )
    running = 0
    i = 0
    while (i < 90):
        time.sleep(1);
        try:
            response = ecs.describe_services(
                cluster=ecs_cluster,
                services=[ecs_service],
            )
            print(json.dumps(response["services"][0], default=str))
            running = response["services"][0]["runningCount"]
        except Exception as e:
            print(e);
        if (running > 0):
            break
        i = i + 1

    response = alb.set_rule_priorities(
        RulePriorities=[
            {
                'Priority': rule_enable_priority,
                'RuleArn': rule_arn,
            },
        ],
    )
    return {}

###############################################################################
# Main handler
###############################################################################
def handler(event, context):
    print(json.dumps(event));
    msg = "GreenLambda : "
    if "httpMethod" in event:
        start(event, context);
        msg = "Starting application : %s" % (ecs_service)
        print(msg);
        headers = event["headers"]
        return {
        	"statusCode": 302,
        	"statusDescription": "302 Found",
        	"isBase64Encoded": False,
        	"headers": {
        	    "Location": "%s://%s%s" % (headers["x-forwarded-proto"], headers["host"], event["path"])
        	}
    	}
    else:
        if "Records" in event:
            CWMessage = json.loads(event["Records"][0]["Sns"]["Message"])
            print(json.dumps(CWMessage));
            print(json.dumps(CWMessage["detail"]));
            status = CWMessage["detail"]["state"]["value"]
            if "ALARM" in status or "INSUFFICIENT_DATA" in status:
                stop(event, context);
                msg = "Stopping application : %s" % (ecs_service)
    print(msg);
    return {
        "statusCode": 200,
        "statusDescription": "200 OK",
        "isBase64Encoded": False,
        "headers": {
            "Content-Type": "text/html"
        },
        "body": "<h1>%s</h1>" % (msg)
    }