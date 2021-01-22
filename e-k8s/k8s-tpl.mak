#
# Front-end to bring some sanity to the litany of tools and switches
# for working with a k8s cluster. Note that this file exercise core k8s
# commands that's independent of the cluster vendor.
#
# All vendor-specific commands are in the make file for that vendor:
# az.mak, eks.mak, gcp.mak, mk.mak
#
# Be sure to set your context appropriately for the log monitor.
#
# The intended approach to working with this makefile is to update select
# elements (body, id, IP, port, etc) as you progress through your workflow.
# Where possible, stodout outputs are tee into .out files for later review.

# These will be filled in by template processor
CREG=ZZ-CR-ID
REGID=ZZ-REG-ID
AWS_REGION=ZZ-AWS-REGION
JAVA_HOME=ZZ-JAVA-HOME
GAT_DIR=ZZ-GAT-DIR

# Keep all the logs out of main directory
LOG_DIR=logs

# These should be in your search path
KC=kubectl
DK=docker
AWS=aws
IC=istioctl
HELM=helm

# Application versions
# Override these by environment variables and `make -e`
APP_VER_TAG=v1
S2_VER=v1
LOADER_VER=v1

# Gatling parameters to be overridden by environment variables and `make -e`
SIM_NAME=ReadUserSim
USERS=1

# Gatling parameters that most of the time will be unchanged
# but which you might override as projects become sophisticated
SIM_FILE=ReadTables.scala
SIM_PACKAGE=proj756
GATLING_OPTIONS=

# Other Gatling parameters---you should not have to change these
GAT=$(GAT_DIR)/bin/gatling.sh
SIM_DIR=gatling/simulations
RES_DIR=gatling/resources
SIM_PACKAGE_DIR=$(SIM_DIR)/$(SIM_PACKAGE)
SIM_FULL_NAME=$(SIM_PACKAGE).$(SIM_NAME)

# Kubernetes parameters that most of the time will be unchanged
# but which you might override as projects become sophisticated
APP_NS=c756ns
ISTIO_NS=istio-system
KIALI_OP_NS=kiali-operator
MONITOR_NS=monitoring
MONITOR_NS_INJECTION=disabled
MON_RELEASE=c756

# ----------------------------------------------------------------------------------------
# -------  Targets to be invoked directly from command line                        -------
# ----------------------------------------------------------------------------------------

# ---  templates:  Instantiate all template files
#
# This is the only entry that *must* be run from k8s-tpl.mak
# (because it creates k8s.mak)
templates:
	tools/process-templates.sh

# --- provision: Provision the entire stack
# This typically is all you need to do to install the sample application and
# all its dependencies
#
# Preconditions:
# 1. Templates have been instantiated (make -f k8s-tpl.mak templates)
# 2. Current context is a running Kubernetes cluster (make -f {az,eks,gcp,mk}.mak start)
#
provision: istio prom kiali deploy

# --- deploy: Deploy and monitor the three microservices
# Use `provision` to deploy the entire stack (including Istio, Prometheus, ...).
# This target only deploys the sample microservices
deploy: appns gw s1 s2 db monitoring
	$(KC) -n $(APP_NS) get gw,vs,deploy,svc,pods

# --- rollout: Rollout new deployments of all microservices
rollout: rollout-s1 rollout-s2 rollout-db

# --- rollout-s1: Rollout a new deployment of S1
rollout-s1: s1
	$(KC) rollout -n $(APP_NS) restart deployment/cmpt756s1

# --- rollout-s2: Rollout a new deployment of S2
rollout-s2: $(LOG_DIR)/s2-$(S2_VER).repo.log  cluster/s2-dpl-$(S2_VER).yaml
	$(KC) -n $(APP_NS) apply -f cluster/s2-dpl-$(S2_VER).yaml | tee $(LOG_DIR)/rollout-s2.log
	$(KC) rollout -n $(APP_NS) restart deployment/cmpt756s2-$(S2_VER) | tee -a $(LOG_DIR)/rollout-s2.log

# --- rollout-db: Rollout a new deployment of DB
rollout-db: db
	$(KC) rollout -n $(APP_NS) restart deployment/cmpt756db

# --- health-off: Turn off the health monitoring for the three microservices
# If you don't know exactly why you want to do this---don't
health-off:
	$(KC) -n $(APP_NS) apply -f cluster/s1-nohealth.yaml
	$(KC) -n $(APP_NS) apply -f cluster/s2-nohealth.yaml
	$(KC) -n $(APP_NS) apply -f cluster/db-nohealth.yaml

# --- scratch: Delete the microservices and everything else in application NS
scratch: clean
	$(KC) delete -n $(APP_NS) deploy --all
	$(KC) delete -n $(APP_NS) svc    --all
	$(KC) delete -n $(APP_NS) gw     --all
	$(KC) delete -n $(APP_NS) dr     --all
	$(KC) delete -n $(APP_NS) vs     --all
	$(KC) delete -n $(APP_NS) se     --all
	$(KC) delete -n $(ISTIO_NS) vs monitoring --ignore-not-found=true
	$(KC) get -n $(APP_NS) deploy,svc,pods,gw,dr,vs,se
	$(KC) get -n $(ISTIO_NS) vs

# --- clean: Delete all the application log files
clean:
	/bin/rm -f $(LOG_DIR)/{s1,s2,db,gw,monvs}*.log $(LOG_DIR)/rollout*.log

# --- dashboard: Start the standard Kubernetes dashboard
# NOTE:  Before invoking this, the dashboard must be installed and a service account created
dashboard: showcontext
	echo Please follow instructions at https://docs.aws.amazon.com/eks/latest/userguide/dashboard-tutorial.html
	echo Remember to 'pkill kubectl' when you are done!
	$(KC) proxy &
	open http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/#!/login

# --- extern: Display status of Istio ingress gateway
# Especially useful for Minikube, if you can't remember whether you invoked its `lb`
# target or directly ran `minikube tunnel`
extern: showcontext
	$(KC) -n $(ISTIO_NS) get svc istio-ingressgateway

# --- lsa: List services in all namespaces
lsa: showcontext
	$(KC) get svc --all-namespaces

# --- ls: Show deploy, pods, vs, and svc of application ns
ls: showcontext
	$(KC) get -n $(APP_NS) gw,vs,svc,deployments,pods

# --- lsd: Show containers in pods for all namespaces
lsd:
	$(KC) get pods --all-namespaces -o=jsonpath='{range .items[*]}{"\n"}{.metadata.name}{":\t"}{range .spec.containers[*]}{.image}{", "}{end}{end}' | sort

# --- reinstate: Reinstate provisioning on a new set of worker nodes
# Do this after you do `up` on a cluster that implements that operation.
# AWS implements `up` and `down`; other cloud vendors may not.
reinstate:
	$(KC) create ns $(APP_NS) | tee $(LOG_DIR)/reinstate.log
	$(KC) label ns $(APP_NS) istio-injection=enabled | tee -a $(LOG_DIR)/reinstate.log
	$(IC) install --set profile=demo | tee -a $(LOG_DIR)/reinstate.log

# --- showcontext: Display current context
showcontext:
	$(KC) config get-contexts

# Run the loader, rebuilding if necessary, starting DynamDB if necessary, building ConfigMaps
loader: dynamodb-start $(LOG_DIR)/loader.repo.log cluster/loader.yaml
	$(KC) -n $(APP_NS) delete --ignore-not-found=true jobs/cmpt756loader
	tools/build-configmap.sh $(RES_DIR)/users.csv cluster/users-header.yaml | kubectl -n $(APP_NS) apply -f -
	tools/build-configmap.sh $(RES_DIR)/music.csv cluster/music-header.yaml | kubectl -n $(APP_NS) apply -f -
	$(KC) -n $(APP_NS) apply -f cluster/loader.yaml | tee $(LOG_DIR)/loader.log

# --- dynamodb-start: Start the AWS DynamoDB service
#
dynamodb-start: $(LOG_DIR)/dynamodb-start.log

# --- dynamodb-stop: Stop the AWS DynamoDB service
#
dynamodb-stop:
	$(AWS) cloudformation delete-stack --stack-name db || true | tee $(LOG_DIR)/dynamodb-stop.log
	@# Rename DynamoDB log so dynamodb-start will force a restart but retain the log
	/bin/mv -f $(LOG_DIR)/dynamodb-start.log $(LOG_DIR)/dynamodb-start-old.log

# --- ls-tables: List the tables and their read/write units for all DynamodDB tables
ls-tables:
	@tools/list-dynamodb-tables.sh $(AWS) $(AWS_REGION)

# --- registry-login: Login to the container registry
#
registry-login:
	# Use '@' to suppress echoing the $CR_PAT to screen
	@/bin/sh -c 'echo ${CR_PAT} | $(DK) login $(CREG) -u $(REGID) --password-stdin'

# --- Variables defined for URL targets
# Utility to get the hostname (AWS) or ip (everyone else) of a load-balanced service
# Must be followed by a namespace and a service
IP_GET_CMD=tools/getip.sh $(KC)

# This expression is reused several times
# Use back-tick for subshell so as not to confuse with make $() variable notation
INGRESS_IP=`$(IP_GET_CMD) $(ISTIO_NS) svc/istio-ingressgateway`

# --- kiali-url: Print the URL to browse Kiali in current cluster
kiali-url:
	@/bin/sh -c 'echo http://$(INGRESS_IP)/kiali'

# --- grafana-url: Print the URL to browse Grafana in current cluster
grafana-url:
	@# Use back-tick for subshell so as not to confuse with make $() variable notation
	@/bin/sh -c 'echo http://`$(IP_GET_CMD) $(MONITOR_NS) svc/grafana-ingress`:3000/'

# --- prometheus-url: Print the URL to browse Prometheus in current cluster
prometheus-url:
	@# Use back-tick for subshell so as not to confuse with make $() variable notation
	@/bin/sh -c 'echo http://`$(IP_GET_CMD) $(MONITOR_NS) svc/prom-ingress`:9090/'

# --- Variables defined for Gatling targets
#
# Suffix to all Gatling commands
# 2>&1:       Redirect stderr to stdout. This ensures the long errors from a
#             misnamed Gatling script are clipped
# | head -18: Display first 18 lines, discard the rest
# &:          Run in background
GAT_SUFFIX=2>&1 | head -18 &

# --- gatling-command: Print the bash command to run a Gatling simulation
# Less convenient than gatling-music or gatling-user (below) but the resulting commands
# from this target are listed by `jobs` and thus easy to kill.
gatling-command:
	@/bin/sh -c 'echo "CLUSTER_IP=$(INGRESS_IP) USERS=1 SIM_NAME=ReadMusicSim make -e -f k8s.mak run-gatling $(GAT_SUFFIX)"'

# --- kiali-svc-token: Get the token
# SAMPLE:  Has embedded secret name!!!
kiali-svc-token:
	$(KC) -n $(MONITOR_NS) get secret/kiali-service-account-token-vt6q5 -o jsonpath='{.data.token}' | base64 -d -

# ----------------------------------------------------------------------------------------
# ------- Targets called by above. Not normally invoked directly from command line -------
# ----------------------------------------------------------------------------------------

# Add the latest active repo for Prometheus
# Only needs to be done once but is idempotent
init-helm:
	$(HELM) repo add prometheus-community https://prometheus-community.github.io/helm-charts

# Install Prometheus and Grafana
install-prom:
	@echo $(HELM) install $(MON_RELEASE) --namespace $(MONITOR_NS) prometheus-community/kube-prometheus-stack > $(LOG_DIR)/install-prometheus.log
	$(KC) create namespace $(MONITOR_NS) || true | tee -a $(LOG_DIR)/install-prometheus.log
	$(KC) label ns $(MONITOR_NS) istio-injection=$(MONITOR_NS_INJECTION) | tee -a $(LOG_DIR)/install-prometheus.log
	$(HELM) install $(MON_RELEASE) -f helm-kube-stack-values.yaml --namespace $(MONITOR_NS) prometheus-community/kube-prometheus-stack | tee -a $(LOG_DIR)/install-prometheus.log
	$(KC) apply -n $(MONITOR_NS) -f monitoring-lb-services.yaml | tee -a $(LOG_DIR)/install-prometheus.log
	$(KC) apply -n $(MONITOR_NS) -f cluster/grafana-flask-configmap.yaml | tee -a $(LOG_DIR)/install-prometheus.log

# Uninstall Prometheus
uninstall-prom:
	@echo $(HELM) uninstall $(MON_RELEASE) --namespace $(MONITOR_NS) > $(LOG_DIR)/uninstall-prometheus.log
	$(HELM) uninstall $(MON_RELEASE) --namespace $(MONITOR_NS) | tee $(LOG_DIR)/uninstall-prometheus.log

# Install Prometheus stack
prom: init-helm install-prom

# Install Kiali operator and Kiali
# Waits for Kiali to be created and begin running. This wait is required
# before installing the three microservices because they
# depend upon some Custom Resource Definitions (CRDs) added
# by Kiali
kiali:
	$(KC) create namespace $(KIALI_OP_NS) || true  | tee $(LOG_DIR)/kiali.log
	$(HELM) install -n $(KIALI_OP_NS) --repo https://kiali.org/helm-charts kiali-operator kiali-operator | tee -a $(LOG_DIR)/kiali.log
	$(KC) apply -n $(MONITOR_NS) -f kiali-cr.yaml | tee -a $(LOG_DIR)/kiali.log
	# Kiali operator can take awhile to start Kiali
	tools/waiteq.sh $(MONITOR_NS) 'app=kiali' '{.items[*]}'              ''        'Kiali' 'Created'
	tools/waitne.sh $(MONITOR_NS) 'app=kiali' '{.items[0].status.phase}' 'Running' 'Kiali' 'Running'

# Uninstall Kiali
uninstall-kiali:
	$(KC) delete -n $(MONITOR_NS) kiali/kiali | tee $(LOG_DIR)/uninstall-kiali.log
	$(HELM) uninstall kiali-operator -n $(KIALI_OP_NS) | tee -a $(LOG_DIR)/uninstall-kiali.log

# Install Istio
istio:
	$(IC) install --set profile=demo --set hub=gcr.io/istio-release | tee $(LOG_DIR)/istio.log
	$(KC) label ns default istio-injection=enabled | tee -a $(LOG_DIR)/istio.log

# Create and configure the application namespace
appns:
	# Appended "|| true" so that make continues even when command fails
	# because namespace already exists
	$(KC) create ns $(APP_NS) || true
	$(KC) label namespace $(APP_NS) --overwrite=true istio-injection=enabled

# Update monitoring virtual service and display result
monitoring: monvs
	$(KC) -n $(MONITOR_NS) get vs

# Update monitoring virtual service
monvs: cluster/monitoring-virtualservice.yaml
	$(KC) -n $(MONITOR_NS) apply -f $< > $(LOG_DIR)/monvs.log

# Update service gateway
gw: cluster/service-gateway.yaml
	$(KC) -n $(APP_NS) apply -f $< > $(LOG_DIR)/gw.log

# Start DynamoDB at the default read and write rates
$(LOG_DIR)/dynamodb-start.log: cluster/cloudformationdynamodb.json
	@# "|| true" suffix because command fails when stack already exists
	@# (even with --on-failure DO_NOTHING, a nonzero error code is returned)
	$(AWS) cloudformation create-stack --stack-name db --template-body file://$< || true | tee $(LOG_DIR)/dynamodb-start.log

# Update S1 and associated monitoring, rebuilding if necessary
s1: $(LOG_DIR)/s1.repo.log cluster/s1.yaml cluster/s1-sm.yaml cluster/s1-vs.yaml
	$(KC) -n $(APP_NS) apply -f cluster/s1.yaml | tee $(LOG_DIR)/s1.log
	$(KC) -n $(APP_NS) apply -f cluster/s1-sm.yaml | tee -a $(LOG_DIR)/s1.log
	$(KC) -n $(APP_NS) apply -f cluster/s1-vs.yaml | tee -a $(LOG_DIR)/s1.log

# Update S2 and associated monitoring, rebuilding if necessary
s2: rollout-s2 cluster/s2-svc.yaml cluster/s2-sm.yaml cluster/s2-vs-$(S2_VER).yaml
	$(KC) -n $(APP_NS) apply -f cluster/s2-svc.yaml | tee $(LOG_DIR)/s2.log
	$(KC) -n $(APP_NS) apply -f cluster/s2-sm.yaml | tee -a $(LOG_DIR)/s2.log
	$(KC) -n $(APP_NS) apply -f cluster/s2-vs-$(S2_VER).yaml | tee -a $(LOG_DIR)/s2.log

# Update DB and associated monitoring, rebuilding if necessary
db: $(LOG_DIR)/db.repo.log cluster/awscred.yaml cluster/dynamodb-service-entry.yaml cluster/db.yaml cluster/db-sm.yaml cluster/db-vs.yaml
	$(KC) -n $(APP_NS) apply -f cluster/awscred.yaml | tee $(LOG_DIR)/db.log
	$(KC) -n $(APP_NS) apply -f cluster/dynamodb-service-entry.yaml | tee -a $(LOG_DIR)/db.log
	$(KC) -n $(APP_NS) apply -f cluster/db.yaml | tee -a $(LOG_DIR)/db.log
	$(KC) -n $(APP_NS) apply -f cluster/db-sm.yaml | tee -a $(LOG_DIR)/db.log
	$(KC) -n $(APP_NS) apply -f cluster/db-vs.yaml | tee -a $(LOG_DIR)/db.log

# Build the s1 service
$(LOG_DIR)/s1.repo.log: s1/Dockerfile s1/app.py s1/requirements.txt
	$(DK) build -t $(CREG)/$(REGID)/cmpt756s1:$(APP_VER_TAG) s1 | tee $(LOG_DIR)/s1.img.log
	$(DK) push $(CREG)/$(REGID)/cmpt756s1:$(APP_VER_TAG) | tee $(LOG_DIR)/s1.repo.log

# Build the s2 service
$(LOG_DIR)/s2-$(S2_VER).repo.log: s2/$(S2_VER)/Dockerfile s2/$(S2_VER)/app.py s2/$(S2_VER)/requirements.txt
	$(DK) build -t $(CREG)/$(REGID)/cmpt756s2:$(S2_VER) s2/$(S2_VER) | tee $(LOG_DIR)/s2-$(S2_VER).img.log
	$(DK) push $(CREG)/$(REGID)/cmpt756s2:$(S2_VER) | tee $(LOG_DIR)/s2-$(S2_VER).repo.log

# Build the db service
$(LOG_DIR)/db.repo.log: db/Dockerfile db/app.py db/requirements.txt
	$(DK) build -t $(CREG)/$(REGID)/cmpt756db:$(APP_VER_TAG) db | tee $(LOG_DIR)/db.img.log
	$(DK) push $(CREG)/$(REGID)/cmpt756db:$(APP_VER_TAG) | tee $(LOG_DIR)/db.repo.log

# Build the loader
$(LOG_DIR)/loader.repo.log: loader/app.py loader/requirements.txt loader/Dockerfile
	$(DK) image build -t $(CREG)/$(REGID)/cmpt756loader:$(LOADER_VER) loader  | tee $(LOG_DIR)/loader.img.log
	$(DK) push $(CREG)/$(REGID)/cmpt756loader:$(LOADER_VER) | tee $(LOG_DIR)/loader.repo.log

# Push all the container images to the container registry
# This isn't often used because the individual build targets also push
# the updated images to the registry
cr:
	$(DK) push $(CREG)/$(REGID)/cmpt756s1:$(APP_VER_TAG) | tee $(LOG_DIR)/s1.repo.log
	$(DK) push $(CREG)/$(REGID)/cmpt756s2:$(S2_VER) | tee $(LOG_DIR)/s2.repo.log
	$(DK) push $(CREG)/$(REGID)/cmpt756db:$(APP_VER_TAG) | tee $(LOG_DIR)/db.repo.log

#
# Other attempts at Gatling commands. Target `gatling-command` is preferred.
# The following may not even work.
#
# General Gatling target: Specify CLUSTER_IP, USERS, and SIM_NAME as environment variables. Full output.
run-gatling:
	JAVA_HOME=$(JAVA_HOME) $(GAT) -rsf $(RES_DIR) -sf $(SIM_DIR) -bf $(GAT_DIR)/target/test-classes -s $(SIM_FULL_NAME) -rd "Simulation $(SIM_NAME)" $(GATLING_OPTIONS)

# The following should probably not be used---it starts the job but under most shells
# this process will not be listed by the `jobs` command. This makes it difficult
# to kill the process when you want to end the load test
gatling-music:
	@/bin/sh -c 'CLUSTER_IP=$(INGRESS_IP) USERS=$(USERS) SIM_NAME=ReadMusicSim JAVA_HOME=$(JAVA_HOME) $(GAT) -rsf $(RES_DIR) -sf $(SIM_DIR) -bf $(GAT_DIR)/target/test-classes -s $(SIM_FULL_NAME) -rd "Simulation $(SIM_NAME)" $(GATLING_OPTIONS) $(GAT_SUFFIX)'

# Different approach from gatling-music but the same problems. Probably do not use this.
gatling-user:
	@/bin/sh -c 'CLUSTER_IP=$(INGRESS_IP) USERS=$(USERS) SIM_NAME=ReadUserSim make -e -f k8s.mak run-gatling $(GAT_SUFFIX)'


# ---------------------------------------------------------------------------------------
# Handy bits for exploring the container images... not necessary
image: showcontext
	$(DK) image ls | tee __header | grep $(REGID) > __content
	head -n 1 __header
	cat __content
	rm __content __header
