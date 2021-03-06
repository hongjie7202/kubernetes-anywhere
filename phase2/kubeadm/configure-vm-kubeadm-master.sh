
# This is not meant to run on its own, but extends phase2/kubeadm/configure-vm-kubeadm.sh

KUBEADM_DIR=/etc/kubeadm
KUBEADM_CONFIG_FILE=$KUBEADM_DIR/kubeadm.yaml

#TODO: we should probably be able to configure POD_NETWORK_CIDR from `make config` in future
# and use the configured value by passing it on to CNI's. We resort to the below hard-coding
# since the current CNI's are not enabled to be configured with the user provided pod-network-cidr.
POD_NETWORK_CIDR=""
if [[ "$KUBEADM_CNI_PLUGIN" == "flannel" ]] || [[ "$KUBEADM_CNI_PLUGIN" == "calico" ]]; then
  POD_NETWORK_CIDR="10.244.0.0/16"
elif [[ "$KUBEADM_CNI_PLUGIN" == "weave" ]]; then
  POD_NETWORK_CIDR="10.32.0.0/12"
fi

mkdir -p $KUBEADM_DIR

# The script has to know the MINOR version from a k8s semantic version,
# so that it can decide which kubeadm config version to use.
# Fetch the semantic version from the server if it's not in semantic
# format already.
# The raw $KUBEADM_KUBERNETES_VERSION can be passed to the config
# as kubeadm can handle that.
KUBEADM_KUBERNETES_SEM_VER=$KUBEADM_KUBERNETES_VERSION
if [[ $KUBEADM_KUBERNETES_SEM_VER = *"ci/"* ]] ||
   [[ $KUBEADM_KUBERNETES_SEM_VER = *"ci-cross/"* ]] ||
   [[ $KUBEADM_KUBERNETES_SEM_VER = *"release/"* ]]; then
  KUBEADM_KUBERNETES_SEM_VER=`curl -sSL https://dl.k8s.io/$KUBEADM_KUBERNETES_VERSION.txt`
fi

# break down the semantic version string
KUBEADM_KUBERNETES_VERSION_MAJOR=`cut -d'.' -f 1 <<< $KUBEADM_KUBERNETES_SEM_VER | cut -d'v' -f 2`
KUBEADM_KUBERNETES_VERSION_MINOR=`cut -d'.' -f 2 <<< $KUBEADM_KUBERNETES_SEM_VER`
KUBEADM_KUBERNETES_VERSION_PATCH=`cut -d'.' -f 3 <<< $KUBEADM_KUBERNETES_SEM_VER | cut -d'-' -f 1`

# set defaults
cat <<EOF |tee $KUBEADM_CONFIG_FILE
kind: MasterConfiguration
kubernetesVersion: "$KUBEADM_KUBERNETES_VERSION"
api:
  advertiseAddress: "$KUBEADM_ADVERTISE_ADDRESSES"
  bindPort: 443
networking:
  podSubnet: "$POD_NETWORK_CIDR"
EOF

# handle v1alpha1
########################################################################
if [[ "$KUBEADM_KUBERNETES_VERSION_MINOR" -lt "11" ]]; then

  # add api version and token
  cat <<EOF |tee -a $KUBEADM_CONFIG_FILE
apiVersion: kubeadm.k8s.io/v1alpha1
token: "$KUBEADM_TOKEN"
EOF

else # handle v1alpha2
########################################################################

  # add api version and token
  cat <<EOF |tee -a $KUBEADM_CONFIG_FILE
apiVersion: kubeadm.k8s.io/v1alpha2
bootstrapTokens:
- token: "$KUBEADM_TOKEN"
EOF

fi
########################################################################

# add cloud provider
if [[ "$KUBEADM_ENABLE_CLOUD_PROVIDER" == true ]]; then
  cat <<EOF |tee -a $KUBEADM_CONFIG_FILE
apiServerExtraArgs:
  cloud-provider: "$CLOUD_PROVIDER"
EOF
fi

# set ipvs
if [[ "$KUBEPROXY_MODE" == "ipvs" ]]; then
  cat <<EOF |tee -a $KUBEADM_CONFIG_FILE
kubeProxy:
  config:
    featureGates:
      SupportIPVSProxyMode: true
    mode: "$KUBEPROXY_MODE"
EOF
fi

# if exist $KUBEADM_FEATURE_GATES is an string in format "key1=values1,key2=value2,.."
# it should be added in the config in an YAML format for the field featureGates - eg:
# featureGates:
#   key1: value1
#   key2: value2
#   etc ...
#NOTE: it is important to avoid the substituion and expression format for a variable. Therefore the usage of evaluated (echo + sed)
KUBEADM_FEATURE_GATES=`echo "$KUBEADM_FEATURE_GATES" | sed -e 's/^[[:space:]]*//'`
if [[ ! -z $KUBEADM_FEATURE_GATES ]]; then
  foptions=`echo $KUBEADM_FEATURE_GATES | sed -e 's/=/: /g;s/,/\\\n  /g'`
  cat <<EOF |tee -a $KUBEADM_CONFIG_FILE
featureGates:
  `echo -e "$foptions"`
EOF
fi

kubeadm init --skip-preflight-checks --config $KUBEADM_CONFIG_FILE
