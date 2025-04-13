provider "alicloud" {}

# 默认资源名称
variable "name" {
  default = "sintan1071-test"
}
# 日志服务项目名称
variable "log_project_name" {
  default = "sintan1071-test-ack-sls-demo"
}
# 可用区
data "alicloud_zones" "default" {
  available_resource_creation = "VSwitch"
}
# 节点ECS实例配置
data "alicloud_instance_types" "default" {
  availability_zone    = data.alicloud_zones.default.zones[0].id
  cpu_core_count       = 2
  memory_size          = 4
  kubernetes_node_role = "Worker"
}
# 专有网络
resource "alicloud_vpc" "default" {
  vpc_name   = var.name
  cidr_block = "10.1.0.0/21"
}
# 交换机
resource "alicloud_vswitch" "default" {
  vswitch_name = var.name
  vpc_id       = alicloud_vpc.default.id
  cidr_block   = "10.1.1.0/24"
  zone_id      = data.alicloud_zones.default.zones[0].id
}

#TODO 数据库实例，需要全部参数化，不要写死
resource "alicloud_db_instance" "instance" {
  engine           = "PostgreSQL"
  engine_version   = "13.0" 
  instance_type    = "pg.n2.2c.2m" 
  instance_storage = "30"
  instance_charge_type = "Postpaid"
  vswitch_id       = alicloud_vswitch.default.id
}

resource "alicloud_rds_account" "account" {
  db_instance_id   = alicloud_db_instance.instance.id
  account_name     = "sintan1071_db_account"
  account_password = "!1QqAaZz111"
}

# 不创建也没关系，本质上RDS会创建默认的链接，
#只是如果用terraform下游还有资源需要引用这个链接的话，则需要创建方便引用
resource "alicloud_db_connection" "connection" {
  instance_id       = alicloud_db_instance.instance.id
  connection_prefix = "sintan1071-db-conn"
}

resource "alicloud_db_database" "db" {
  instance_id = alicloud_db_instance.instance.id
  name        = "sintan1071_db"

  # 加强显式依赖，确保实例和账户也已创建
  depends_on = [
    alicloud_db_instance.instance,
    alicloud_rds_account.account
  ]
}

resource "alicloud_db_account_privilege" "privilege" {
  instance_id  = alicloud_db_instance.instance.id
  account_name = alicloud_rds_account.account.account_name
  privilege    = "DBOwner" # 其他类型：ReadOnly
  db_names     = [alicloud_db_database.db.name]

  # 加强显式依赖，确保实例和账户也已创建
  depends_on = [
    alicloud_db_instance.instance,
    alicloud_rds_account.account,
    alicloud_db_database.db
  ]
}

# kubernetes托管版
resource "alicloud_cs_managed_kubernetes" "default" {
  worker_vswitch_ids = [alicloud_vswitch.default.id]
  # kubernetes集群名称的前缀。与name冲突。如果指定，terraform将使用它来构建唯一的集群名称。默认为" Terraform-Creation"。
  name_prefix = var.name
  # 是否在创建kubernetes集群时创建新的nat网关。默认为true。
  new_nat_gateway = true
  # pod网络的CIDR块。当cluster_network_type设置为flannel，你必须设定该参数。它不能与VPC CIDR相同，并且不能与VPC中的Kubernetes集群使用的CIDR相同，也不能在创建后进行修改。集群中允许的最大主机数量：256。
  pod_cidr = "172.20.0.0/16"
  # 服务网络的CIDR块。它不能与VPC CIDR相同，不能与VPC中的Kubernetes集群使用的CIDR相同，也不能在创建后进行修改。
  service_cidr = "172.21.0.0/20"
  # 是否为API Server创建Internet负载均衡。默认为false。
  slb_internet_enabled = true
}

resource "alicloud_cs_kubernetes_node_pool" "default" {
  node_pool_name         = var.name
  cluster_id   = alicloud_cs_managed_kubernetes.default.id
  vswitch_ids  = [alicloud_vswitch.default.id]
  # ssh登录集群节点的密码。您必须指定password或key_name kms_encrypted_password字段。
  password = "!1QqAaZz111"
  # kubernetes集群的总工作节点数。
  desired_size = 2
  # 是否为kubernetes的节点安装云监控。
  install_cloud_monitor = true
  # 节点的ECS实例类型。为单个AZ集群指定一种类型，为MultiAZ集群指定三种类型。您可以通过数据源instance_types获得可用的kubernetes主节点实例类型
  # instance_types        = ["ecs.c8y.small"]
  instance_types = [data.alicloud_instance_types.default.instance_types[0].id]
  # 节点的系统磁盘类别。其有效值为cloud_ssd和cloud_efficiency。默认为cloud_efficiency。
  system_disk_category  = "cloud_ssd"
  system_disk_size      = 20
  # data_disks {
  #   category = "cloud_ssd"
  #   size = "100"
  # }
}

# Redis 实例配置
resource "alicloud_kvstore_instance" "redis_instance" {
  # 实例名称，使用变量 "name" 加上后缀 "-redis"
  instance_name     = "${var.name}-redis"
  
  # 实例类型，指定为 Redis
  instance_type     = "Redis"
  # Redis 引擎版本，例如 5.0, 6.0, 7.0 等，请根据需要选择
  engine_version    = "5.0" 
  # 实例规格，例如 redis.basic.small.default (1G内存基础版)
  # 或 redis.cluster.sharding.2g.2db.0ro.ln (2G集群版)
  # 请根据需求和预算选择合适的规格
  instance_class    = "redis.basic.small.default" 
  
  # 网络配置：指定实例所属的交换机 ID
  vswitch_id        = alicloud_vswitch.default.id
  # 网络配置：指定实例所属的专有网络 VPC ID
  # 虽然 vswitch_id 可以推断出 vpc_id，但明确指定更清晰
  # vpc_id            = alicloud_vpc.default.id 
  
  # 付费模式：PostPaid 表示按量付费，PrePaid 表示包年包月
  payment_type      = "PostPaid"
  # 可用区 ID，使用数据源查询到的第一个可用区
  zone_id           = data.alicloud_zones.default.zones[0].id
  
  # 安全设置：访问 Redis 实例的密码
  # 警告：请务必替换为强密码，并考虑使用密钥管理服务
  password          = "!1QqAaZz111" 
  
  # 安全设置：允许访问 Redis 实例的 IP 地址列表或 CIDR 段
  # 这里设置为允许 VPC 内所有 IP 访问，可根据需要收紧
  security_ips      = [alicloud_vpc.default.cidr_block] 
}

# 输出 Redis 实例的连接信息
output "redis_connection_address" {
  description = "Redis 实例的私网连接地址 (域名)"
  value       = alicloud_kvstore_instance.redis_instance.connection_domain
}

output "redis_port" {
  description = "Redis 实例的连接端口"
  value       = alicloud_kvstore_instance.redis_instance.port
}