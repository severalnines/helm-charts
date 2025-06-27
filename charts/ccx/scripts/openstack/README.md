# Check and verify openstack credentials

The script `test-openstack-secrets.py` can be used to verify your openstack credentials before creating them as k8s secrets.
The following packages are needed:

```
pyyaml
openstacksdk
boto3
```
Save them in `requirements.txt`. 

## To install:

```
pip install -r requirements.txt
```

or

```
pip install pyyaml
pip install openstacksdk
pip install boto3
```

## Run:


```
python ./test-openstack-secrets.py openstack-secret.yaml
```

If all is ok you will see:

```

🔎 Debug: Attempting OpenStack authentication with these arguments:
...
✅ MYCLOUD_OpenStack authentication: SUCCESS

🔎 Debug: Attempting S3 authentication with these arguments:
...
✅ MYCLOUD_S3 authentication: SUCCESS

```

The input secrets file must have the following format (change `MYCLOUD` to the cloud identifier you want to use):

```
---
apiVersion: v1
kind: Secret
metadata:
  name: openstack
type: Opaque
stringData:
  MYCLOUD_AUTH_URL: https://....
  MYCLOUD_PASSWORD: xxxxxx
  MYCLOUD_PROJECT_ID: 5b8e951e41f34b5394bb7cf2323
  MYCLOUD_USER_DOMAIN: mydomain
  MYCLOUD_USERNAME: bob@example.com
  MYCLOUD_USER_DOMAIN_NAME: mydomain
---
apiVersion: v1
kind: Secret
metadata:
  name: openstack-s3
type: Opaque
stringData:
  MYCLOUD_S3_ENDPOINT: https://s3...
  MYCLOUD_S3_ACCESSKEY: <ACCESSKEY>
  MYCLOUD_S3_SECRETKEY: <SECRETKEY>
  MYCLOUD_S3_BUCKETNAME: ccx
  MYCLOUD_S3_INSECURE_SSL: "false" # Set to 'true' if your S3 connection is unencrypted (http)  or 'false' if it is (https).
```


