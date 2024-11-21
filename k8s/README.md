# 利用k8s建構Spark集群 Spark on k8s

## 前置準備

使用K8s建構Spark集群前，請確保以下前置條件已完成：

* 已設定好k8s集群，包涵CRI以及CNI等部分

## 簡介

在k8s集群上建構Spark集群，與過往的Standalone以及hadoop等設定方式不同，不會有常駐資源，設定上以k8s的Service Account以及對應的權限，在接受任務的同時才會進行細部元件的建構。

## 設定

要在k8s上使用Spark，需要建立一個Service Account，並透過Role以及Role Binding等設定，給予對應的權限，允許該帳號進行資源的分配以及建構。接下來，我們將建立一個命名空間`spark`，並在此空間中進行後續的設定：

## Namespace

首先，我們先建構一個命名空間：

```
apiVersion: v1
kind: Namespace
metadata:
  name: spark
```

### Service Account

接下來，我們設定一個名為`spark-account`的帳號，並設定其對應的Token：

```
apiVersion: v1
kind: ServiceAccount
metadata:
  name: spark-account
  namespace: spark
automountServiceAccountToken: true
---
apiVersion: v1
kind: Secret
metadata:
  name: spark-sa-secret
  namespace: spark
  annotations:
    kubernetes.io/service-account.name: spark-account-new
type: kubernetes.io/service-account-token
```

### Role

接下來，我們將建立一個角色（Role），並給予這個角色在`spark`命名空間中，一定的權限：

```
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: spark-role
  namespace: spark
rules:
- apiGroups: [""]
  resources: ["pods", "persistentvolumeclaims", "configmaps", "services"]
  verbs: ["get", "deletecollection", "create", "list", "watch", "delete"]
```

### Role Binding

要把權限以及角色進行綁定，需要用到`Role Binding`，這是RBAC的驗證方式中，必要的步驟。（在這裡我們不展開RBAC的相關內容。）

```
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: spark-rolebinding
subjects:
- kind: ServiceAccount
  name: spark-account
  namespace: spark
roleRef:
  kind: Role
  name: spark-role
  apiGroup: rbac.authorization.k8s.io
```

在完成`Namespace`、`Service Account`、`Role`以及`Role Binding`的設定後，對於在k8s上建構Spark集群的設定已經完成。接下來我們將實際示範如何使用一個部署作為中轉，讓PySpark可以透過此部署來在k8s集群中啟動執行元件，並進行計算。

## 實務演示 － 建構部署，並使用PySpark與集群互動

### 設定部署

我們將使用下方所示的設定來進行部署的建構：

```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spark-client
  namespace: spark
spec:
  replicas: 1
  selector:
    matchLabels:
      app: "spark-client"
    
    template:
      metadata:
        labels:
          app: "spark-client"
      
      spec: 
        serviceAccountName: "spark-account"
        containers:
        - name: "sparl-client"
          image: "davidho9717/spark:3.4.4-jupyter"
          command: ["jupyter"]
          args: ["lab", "--allow-root", "--ServerApp.allow_remote_access=true", "--ip=0.0.0.0"]
          ports:
            - containerPort: 8888
              name: notebook
            - containerPort: 8002
              name: driver-port
            - containerPort: 8001
              name: block-manager
            - containerPort: 4040
              name: web-ui
            - containerPort: 7337
              name: shuffle-service
```

在這個部署中，我們使用一個預先建構的Spark映像檔作為容器基礎，在啟動此部署時，建立一個Jupyter Lab為操作介面。此外，我們在此部署中，暴露了五個連接埠，為後續使用做準備。

### 設定服務

在k8s中，要讓部署以及Pod的連接埠能被集群外所存取，需要進行服務（Service）的設定。以下設定是我們所使用的：

```
apiVersion: v1
kind: Service
metadata:
  name: spark-client-svc
  namespace: spark
spec:
  selector:
    app: spark-client
  ports:
    - name: "notebook"
      port: 8888
      targetPort: 8888
    - name: "block-manager"
      port: 8001
      targetPort: 8001
    - name: "driver-port"
      port: 8002
      targetPort: 8002
    - name: "web-ui"
      port: 4040
      targetPort: 4040
      - name: "suffle-service"
      port: 7337
      targetPort: 7337
```

### 設定Ingress

在k8s中，我們可以使用Ingress來包裝服務，讓服務可以更輕易的被存取。在本示範中，所使用的Ingress為Traefik，若使用不同的Ingress控制器，可能無法重現效果。

```
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: spark-ingress
  namespace: spark

spec:
  rules:
    - host: spark-jupyter.homelab.me
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name:  spark-client-svc
                port:
                  number: 8888
    - host: spark-webui.homelab.me
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name:  spark-client-svc
                port:
                  number: 4040
    - host: spark-shffle.homelab.me
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name:  spark-client-svc
                port:
                  number: 7337
    - host: spark-block.homelab.me
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name:  spark-client-svc
                port:
                  number: 8001
    - host: spark-driver.homelab.me
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name:  spark-client-svc
                port:
                  number: 8002
```

在上方的設定中，我們為五個連接埠以及其對應的服務，設定了不同的域名。接下來請在`/etc/hosts`中加入以下內容，來取代DNS的解析服務。

```
<your k8s IP>  <domain name>
```

其中，`<your k8s IP>`為k8s的IP位置，而`<domain name>`則是上方的五個域名。請注意，每個域名需要獨立一筆設定。

### 取得Tolen以及證書

為了使用PySpark，我們還需要取得幾項資料：

* Service Account Token

```
kubectl get secret -n spark spark-sa-secret -o jsonpath={.data.token} | base64 -d
```

* 自簽SSL證書

```
echo -n|openssl s_client -connect 192.168.0.42:6443|openssl x509 -outform PEM > self_signed.pem
```

### 連結至Jupyter

接下來，我們可以透過以下的連結來連線至Jupyter Lab

```
http://spark-jupyter.homelab.me
```

網頁會要求輸入驗證碼，此驗證法可以透過以下的指令取得：

```
kubectl get pods -n spark | grep client | awk '{print $1}' | xargs kubectl logs -n spark | grep http:
```

截取獲得的網址中`token=`後方的字串作為驗證碼即可。

### 使用PySpark建立SparkSession

接下來，我們將使用PySpark建立SparkSession並與Spark集群互動。首先，將先前取得的`self_signed.pem`上傳至Jupyter Lab。接下來輸入以下內容：

```
from pyspark.sql import SparkSession
spark = (
    SparkSession
    .builder
    .master("k8s://https://192.168.0.42:6443")
    .appName("spark-jupyter")
    .config("spark.executor.instances", 1)
    .config("spark.submit.deployMode", "client")
    .config("spark.driver.host", "spark-client-svc")
    .config("spark.driver.port", "8002")
    .config("spark.blockManager.port", "8001")
    .config("spark.kubernetes.container.image", "apache/spark:3.4.4")
    .config("spark.kubernetes.namespace", "spark")
    .config("spark.kubernetes.authenticate.driver.serviceAccountName", "spark-account")
    .config("spark.kubernetes.authenticate.executor.serviceAccountName", "spark-account")
    .config("spark.kubernetes.authenticate.submission.oauthToken", sa_token)
    .config("spark.kubernetes.authenticate.submission.caCertFile", "/opt/spark/self_signed.pem")
    .config("spark.eventLog.enabled", "false")
    .config("spark.driver.cores", "2")
    .config("spark.driver.memory", "500M")
    .config("spark.executor.cores", "2")
    .config("spark.executor.memory", "500M")
    .config("spark.cores.max", "5")
    .config("spark.dynamicAllocation.enables", "false")
    .config("spark.shuffle.service.enables", "false")
    .config("spark.driver.bindAddress", "spark-client-svc")
    .getOrCreate()
)
```

執行以上程式碼後，若是正常建立Spark連線，就可以使用`spark`來進行後續的互動。