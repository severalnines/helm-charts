import argparse
import yaml
import boto3
from botocore.exceptions import ClientError
from openstack import connection
from openstack import exceptions as os_exceptions

def detect_prefix(d, required_keys):
    """
    Detects the cloud prefix (e.g. MYCLOUD, GROKCLOUD) used for keys.
    """
    for k in d:
        for req in required_keys:
            if k.endswith(req):
                prefix = k[:-len(req)]
                if all((prefix + rk) in d for rk in required_keys):
                    return prefix
    raise Exception("Could not detect prefix for required keys: {}".format(required_keys))

def load_secrets(filename):
    """
    Loads secrets from the given YAML file and returns a dict keyed by secret name.
    """
    with open(filename) as f:
        docs = list(yaml.safe_load_all(f))
    secret_data = {}
    for doc in docs:
        name = doc['metadata']['name']
        secret_data[name] = doc['stringData']
    return secret_data

def check_openstack(data):
    required = ['AUTH_URL', 'USERNAME', 'PASSWORD', 'USER_DOMAIN_NAME']
    prefix = detect_prefix(data, required)

    auth_args = {
        'auth_url': data.get(f'{prefix}AUTH_URL'),
        'username': data.get(f'{prefix}USERNAME'),
        'password': data.get(f'{prefix}PASSWORD'),
        'user_domain_name': data.get(f'{prefix}USER_DOMAIN_NAME'),
    }
    if f'{prefix}PROJECT_ID' in data and data[f'{prefix}PROJECT_ID']:
        auth_args['project_id'] = data[f'{prefix}PROJECT_ID']
    elif f'{prefix}PROJECT_NAME' in data and data[f'{prefix}PROJECT_NAME']:
        auth_args['project_name'] = data[f'{prefix}PROJECT_NAME']
    else:
        print(f"❌ {prefix}OpenStack authentication: FAILED (Missing PROJECT_ID or PROJECT_NAME)")
        return
    if f'{prefix}PROJECT_DOMAIN_NAME' in data and data[f'{prefix}PROJECT_DOMAIN_NAME']:
        auth_args['project_domain_name'] = data[f'{prefix}PROJECT_DOMAIN_NAME']

    # Print debug, masking the password
    print(f"\n🔎 Debug: Attempting OpenStack authentication with these arguments:")
    for k, v in auth_args.items():
        if k == "password":
            print(f"   {k}: ***hidden***")
        else:
            print(f"   {k}: {v}")

    try:
        conn = connection.Connection(**auth_args)
        if conn.authorize():
            print(f"✅ {prefix}OpenStack authentication: SUCCESS")
        else:
            print(f"❌ {prefix}OpenStack authentication: FAILED (Not authorized)")
    except os_exceptions.HttpException as e:
        if "forbidden" in str(e).lower() or "403" in str(e):
            print(f"✅ {prefix}OpenStack authentication: SUCCESS (but limited privileges)")
        else:
            print(f"❌ {prefix}OpenStack authentication: FAILED ({e})")
    except Exception as e:
        print(f"❌ {prefix}OpenStack authentication: FAILED ({e.__class__.__name__}: {e})")

def check_s3(data):
    required = ['S3_ENDPOINT', 'S3_ACCESSKEY', 'S3_SECRETKEY', 'S3_BUCKETNAME', 'S3_INSECURE_SSL']
    try:
        prefix = detect_prefix(data, required)
        # Collect the parameters used for debug printing
        s3_params = {
            'endpoint_url': data.get(f'{prefix}S3_ENDPOINT'),
            'aws_access_key_id': data.get(f'{prefix}S3_ACCESSKEY'),
            'aws_secret_access_key': '***hidden***',  # Don't print real secret
            'verify': (data.get(f'{prefix}S3_INSECURE_SSL', '').lower() != 'true'),
            'region_name': 'us-east-1'
        }
        print(f"\n🔎 Debug: Attempting S3 authentication with these arguments:")
        for k, v in s3_params.items():
            print(f"   {k}: {v}")

        s3_client = boto3.client(
            's3',
            endpoint_url=s3_params['endpoint_url'],
            aws_access_key_id=s3_params['aws_access_key_id'],
            aws_secret_access_key=data.get(f'{prefix}S3_SECRETKEY'),  # use real value for client
            verify=s3_params['verify'],
            region_name=s3_params['region_name']
        )
        # Just test that listing works, don't require the bucket to exist
        s3_client.list_buckets()
        print(f"✅ {prefix}S3 authentication: SUCCESS")
    except ClientError as e:
        print(f"❌ {prefix}S3 authentication: FAILED ({e})")
    except Exception as e:
        print(f"❌ {prefix}S3 authentication: FAILED ({e.__class__.__name__}: {e})")


def main():
    parser = argparse.ArgumentParser(description="Test OpenStack and S3 secrets.")
    parser.add_argument("secrets_file", help="Path to the secrets YAML file")
    args = parser.parse_args()

    try:
        secrets = load_secrets(args.secrets_file)
    except Exception as e:
        print(f"❌ Failed to load secrets file: {e.__class__.__name__}: {e}")
        return

    if 'openstack' in secrets:
        check_openstack(secrets['openstack'])
    else:
        print("⚠️  No 'openstack' secret found in the file.")

    if 'openstack-s3' in secrets:
        check_s3(secrets['openstack-s3'])
    else:
        print("⚠️  No 'openstack-s3' secret found in the file.")

if __name__ == "__main__":
    main()

