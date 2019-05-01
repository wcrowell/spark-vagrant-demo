ip_address=$1
hostname=$2
spark_version=$3
zookeeper_version=$4
scala_version=$5

printf "spark_version: %s zookeeper_version: %s scala_version: %s for %s at address %s" $spark_version $zookeeper_version $scala_version $hostname $ip_address

# Add spark to sudoers list, so we do not have to prefix every command with sudo.
#echo "%spark  ALL=(ALL)       ALL\n" >> /etc/sudoers

# Append virtual machines to /etc/hosts for the private network.
cat /common/hosts >> /etc/hosts

date > /etc/vagrant_provisioned_at

# Add the spark and zookeeper user accounts
useradd -m -s /bin/bash -U spark -u 676
useradd -m -s /bin/bash -U zookeeper -u 677
# Remove password from spark and zookeeper so we can stop/start spark without sudo or password
passwd -d spark 
passwd -d zookeeper 
# Add spark and zookeeper accounts to wheel group
usermod -aG wheel spark 
usermod -aG wheel zookeeper 
chown -R spark:spark /home/spark
chown -R zookeeper:zookeeper /home/zookeeper

# Install wget and OpenJDK 
yum -y install wget --nogpgcheck
yum -y install java-1.8.0-openjdk.x86_64 --nogpgcheck

# Get Spark, Zookeeper, and Scala
cd /common
wget -N --no-verbose https://www-us.apache.org/dist/spark/spark-${spark_version}/spark-${spark_version}-bin-hadoop2.7.tgz
wget -N --no-verbose https://www-us.apache.org/dist/zookeeper/zookeeper-${zookeeper_version}/zookeeper-${zookeeper_version}.tar.gz
wget -N --no-verbose https://downloads.lightbend.com/scala/${scala_version}/scala-${scala_version}.rpm

# Extract Spark binary into /opt/spark
cd /opt
tar xzf /common/spark-${spark_version}-bin-hadoop2.7.tgz
ln -s spark-${spark_version}-bin-hadoop2.7 ./spark
cd spark 
chown -R spark:spark /opt/spark/*

# Set the master
echo "spark.master spark://${hostname}:7077" >> /opt/spark/conf/spark-defaults.conf.template

# Create a slave
cp /opt/spark/conf/slaves.template /opt/spark/conf/slaves
sed -i 's/localhost/${hostname}/g' /opt/spark/conf/slaves;

# Extract Zookeeper binary into /opt/zookeeper
cd /opt
tar xzf /common/zookeeper-${zookeeper_version}.tar.gz 
ln -s zookeeper-${zookeeper_version} ./zookeeper
cd zookeeper
mkdir data
chown -R zookeeper:zookeeper /opt/zookeeper/*

# Install Scala
rpm -i /common/scala-${scala_version}.rpm

# Setting the hostname allows me to see what machine I am on from the prompt
hostnamectl set-hostname ${hostname}

cp /common/zoo.cfg /opt/zookeeper/conf/zoo.cfg
chown zookeeper:zookeeper /opt/zookeeper/conf/zoo.cfg
cp /common/zookeeper.service /usr/lib/systemd/system/zookeeper.service

# Add Spark and Scala environment variables
SPARK_BASH_PROFILE="/home/spark/.bashrc"

printf "export SCALA_HOME=/usr/share/scala\n" >> $SPARK_BASH_PROFILE
printf "export SPARK_HOME=/home/spark/spark-2.4.1-bin-hadoop2.7\n" >> $SPARK_BASH_PROFILE
printf "export SPARK_WORKER_MEMORY=1g" >> $SPARK_BASH_PROFILE
printf "export SPARK_WORKER_INSTANCES=2" >> $SPARK_BASH_PROFILE
printf "export SPARK_WORKER_DIR=/home/spark/sparkdata" >> $SPARK_BASH_PROFILE
printf "export PATH=$HOME/bin:$SCALA_HOME/bin:$PATH" >> $SPARK_BASH_PROFILE

# Reload the changes to the .service files
systemctl daemon-reload
systemctl enable zookeeper.service

# Create password-less ssh for the spark user
mkdir /etc/ssh/spark
chmod 755 /etc/ssh/spark

cat /home/vagrant/.ssh/authorized_keys >> /etc/ssh/spark/authorized_keys
if test -f "/common/${hostname}_id_rsa"; then
  rm -rf "/common/${hostname}_id_rsa"
fi
sudo -u spark ssh-keygen -t rsa -P "" -f /home/spark/.ssh/id_rsa
cp /home/spark/.ssh/id_rsa.pub /common/${hostname}_id_rsa.pub
cat /common/*_id_rsa.pub >> /etc/ssh/spark/authorized_keys
chmod 644 /etc/ssh/spark/authorized_keys

sed -i 's/AuthorizedKeysFile\t.ssh\/authorized_keys/AuthorizedKeysFile\t\/etc\/ssh\/spark\/authorized_keys/g' /etc/ssh/sshd_config;

# Restart sshd for the change to take affect
echo Restarting sshd...
service sshd restart
echo Restarted sshd...

echo Provisioning completed for Apache Spark and Zookeeper...

