#
# Instantiate a blueprints from the previously created templates
#


resource "apstra_datacenter_blueprint" "gpus_bp" {
  name        = "Backend GPU Fabric"
  template_id = var.all_qfx_backend ? apstra_template_rack_based.AI_Cluster_GPUs_Medium.id : apstra_template_rack_based.AI_Cluster_GPUs_Large.id
}

resource "apstra_datacenter_blueprint" "storage_bp" {
  name        = "Backend Storage Fabric"
  template_id = apstra_template_rack_based.AI_Cluster_Storage.id
}

resource "apstra_datacenter_blueprint" "mgmt_bp" {
  name        = "Frontend Management Fabric"
  template_id = apstra_template_rack_based.AI_Cluster_Mgmt.id
}

#
# Populate the blueprint ASNs and addressing from resource pools
#

locals {
  blueprints = [
    apstra_datacenter_blueprint.gpus_bp,
    apstra_datacenter_blueprint.mgmt_bp,
    apstra_datacenter_blueprint.storage_bp,
  ]

  asn_pool_roles = ["spine_asns", "leaf_asns"]
  first_asn      = 100
  asn_pool_size  = 100

#
# 10.0.0.0/24, 10.0.1.0/24, 10.0.2.0/24 for the GPU fabric
# 10.0.3.0/24, 10.0.4.0/24, 10.0.5.0/24 for the mgmt fabric
# 10.0.6.0/24, 10.0.7.0/24, 10.0.8.0/24 for the storage fabric
#
  ipv4_pool_roles       = ["spine_loopback_ips", "leaf_loopback_ips", "spine_leaf_link_ips"]
  ipv4_block           = "10.0.0.0/8"
  ipv4_pool_extra_bits = 16
}

resource "apstra_asn_pool" "all" {
  count = (length(local.blueprints) * length(local.asn_pool_roles))
  name = format("%s %s",
    local.blueprints[floor(count.index / length(local.asn_pool_roles))].name,
    replace(title(replace(local.asn_pool_roles[count.index % length(local.asn_pool_roles)], "_", " ")), "Asns", "ASNs"),
  )
  ranges = [
    {
      first = local.first_asn + (count.index * local.asn_pool_size)
      last  = local.first_asn + (count.index * local.asn_pool_size) + local.asn_pool_size - 1
    }
  ]
}

resource "apstra_datacenter_resource_pool_allocation" "asns" {
  count        = (length(local.blueprints) * length(local.asn_pool_roles))
  blueprint_id = local.blueprints[floor(count.index / length(local.asn_pool_roles))].id
  pool_ids     = [apstra_asn_pool.all[count.index].id]
  role         = local.asn_pool_roles[count.index % length(local.asn_pool_roles)]
}

resource "apstra_ipv4_pool" "all" {
  count   = (length(local.blueprints) * length(local.ipv4_pool_roles))
  name = format("%s %s",
    local.blueprints[floor(count.index / length(local.ipv4_pool_roles))].name,
    replace(title(replace(local.ipv4_pool_roles[count.index % length(local.ipv4_pool_roles)], "_", " ")), "Ips", "IPs"),
  )
  subnets = [{ network = cidrsubnet(local.ipv4_block, local.ipv4_pool_extra_bits, count.index) }]
}

resource "apstra_datacenter_resource_pool_allocation" "ipv4" {
  count        = (length(local.blueprints) * length(local.ipv4_pool_roles))
  blueprint_id = local.blueprints[floor(count.index / length(local.ipv4_pool_roles))].id
  pool_ids     = [apstra_ipv4_pool.all[count.index].id]
  role = local.ipv4_pool_roles[count.index % length(local.ipv4_pool_roles)]
}


#
# Assign interface map for spines
#
resource "apstra_datacenter_device_allocation" "frontend_spines" {
  count                    = 2
  blueprint_id             = apstra_datacenter_blueprint.mgmt_bp.id
  initial_interface_map_id = apstra_interface_map.AI-Spine_32x400.id
  node_name                = "spine${count.index + 1}"
  deploy_mode              = "deploy"
}

resource "apstra_datacenter_device_allocation" "storage_spines" {
  count                    = 2
  blueprint_id             = apstra_datacenter_blueprint.storage_bp.id
  initial_interface_map_id = apstra_interface_map.AI-Spine_32x400.id
  node_name                = "spine${count.index + 1}"
  deploy_mode              = "deploy"
}

resource "apstra_datacenter_device_allocation" "gpus_spines" {
  count                    = 2
  blueprint_id             = apstra_datacenter_blueprint.gpus_bp.id
  initial_interface_map_id = var.all_qfx_backend ? apstra_interface_map.AI-Spine_64x400.id : apstra_interface_map.AI-Spine-PTX10008_72x400.id
  node_name                = "spine${count.index + 1}"
  deploy_mode              = "deploy"
}

#
# Assign interface map for leafs
#
resource "apstra_datacenter_device_allocation" "frontend-leafs1" {
  blueprint_id             = apstra_datacenter_blueprint.mgmt_bp.id
  initial_interface_map_id = apstra_interface_map.AI-Leaf_16x400_64x100.id
  node_name                = format("%s_001_leaf1", replace(lower(apstra_rack_type.Frontend-Mgmt-AI.name), "-", "_"))
  deploy_mode              = "deploy"
}

resource "apstra_datacenter_device_allocation" "frontend_leafs2" {
  blueprint_id             = apstra_datacenter_blueprint.mgmt_bp.id
  initial_interface_map_id = apstra_interface_map.AI-Leaf_16x400_64x100.id
  node_name                = format("%s_001_leaf1", replace(lower(apstra_rack_type.Frontend-Mgmt-Weka.name), "-", "_"))
  deploy_mode              = "deploy"
}

resource "apstra_datacenter_device_allocation" "storage-leafs1" {
  count                    = 2
  blueprint_id             = apstra_datacenter_blueprint.storage_bp.id
  initial_interface_map_id = apstra_interface_map.AI-Leaf_16x400_32x200.id
  node_name                = format("%s_001_leaf%s", replace(lower(apstra_rack_type.Storage-AI.name), "-", "_"), count.index + 1)
  deploy_mode              = "deploy"
}

resource "apstra_datacenter_device_allocation" "storage_leafs2" {
  count                    = 2
  blueprint_id             = apstra_datacenter_blueprint.storage_bp.id
  initial_interface_map_id = apstra_interface_map.AI-Leaf_16x400_32x200.id
  node_name                = format("%s_001_leaf%s", replace(lower(apstra_rack_type.Storage-Weka.name), "-", "_"), count.index + 1)
  deploy_mode              = "deploy"
}

resource "apstra_datacenter_device_allocation" "gpu-leafs1" {
  count                    = 8
  blueprint_id             = apstra_datacenter_blueprint.gpus_bp.id
  initial_interface_map_id = apstra_interface_map.AI-LabLeaf_Small.id
  node_name                = format("%s_001_leaf%s", replace(lower(apstra_rack_type.GPU-Backend_Sml.name), "-", "_"), count.index + 1)
  deploy_mode              = "deploy"
}

resource "apstra_datacenter_device_allocation" "gpu_leafs2" {
  count                    = 8
  blueprint_id             = apstra_datacenter_blueprint.gpus_bp.id
  initial_interface_map_id = apstra_interface_map.AI-LabLeaf_Medium.id
  node_name                = format("%s_001_leaf%s", replace(lower(apstra_rack_type.GPU-Backend_Med.name), "-", "_"), count.index + 1)
  deploy_mode              = "deploy"
}



#
# Add configlets to the fabrics. We will assume the DLB configlet and DCQCN configlet
# are not necessary for the management fabric/blueprint.
#

resource "apstra_datacenter_configlet" "DLB_GPUS_BP" {
  blueprint_id = apstra_datacenter_blueprint.gpus_bp.id
  catalog_configlet_id = apstra_configlet.DLB.id
  condition = var.all_qfx_backend ? "role in [\"leaf\", \"spine\"]" : "role in [\"leaf\"]"
}

resource "apstra_datacenter_configlet" "DLB_STORAGE_BP" {
  blueprint_id = apstra_datacenter_blueprint.storage_bp.id
  catalog_configlet_id = apstra_configlet.DLB.id
  condition = "role in [\"leaf\", \"spine\"]"
}