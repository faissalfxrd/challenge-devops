import random

def lambda_handler(event, context):
    status_codes = [200, 300, 400, 500, 503, 507]
    random_code = random.choice(status_codes)
    return {
        'statusCode': random_code,
        'body': f'Status Code: {random_code}'
    }
