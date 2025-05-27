FROM docker.base

EXPOSE 9006

RUN useradd -u 1000 rutger

RUN apt-get  update && \
  apt-get install -y locales && rm -rf /var/lib/apt
#  apt-get install -y openjdk-11-jre maven postgresql-client locales

RUN locale-gen en_US.UTF-8
ARG LOGHI_VERSION=1.0-SNAPSHOT

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8
ENV LOGHI_VERSION=${LOGHI_VERSION}

COPY loghi-tooling /src/loghi-tooling
COPY prima-core-libs /src/prima-core-libs
COPY dependency-check-data /root/.m2/repository/org/owasp/dependency-check-data

WORKDIR /src/prima-core-libs/java

RUN apt-get update && apt-get --no-install-recommends install -y openjdk-11-jre maven postgresql-client libdc1394-22 libavcodec58 libavformat58 libswscale5 libtbb2 git \
  && mvn deploy:deploy-file -Durl=file:///$HOME/repo -Dfile=/usr/local/share/java/opencv4/opencv-4100.jar -DgroupId=org.opencv -DartifactId=opencv -Dpackaging=jar -Dversion=4.10.0 \
  && mvn clean package
RUN cd /src \
  && git clone https://github.com/rvankoert/langident.git \
  && cd langident \
  && mvn clean package \
  && mvn deploy:deploy-file -Durl=file:///$HOME/repo -Dfile=target/langident-1.0.5-SNAPSHOT.jar -DgroupId=nl.knaw.huygens.pergamon.nlp -DartifactId=langident -Dpackaging=jar -Dversion=1.0.5

#	  && mvn clean package \
#  && mvn org.owasp:dependency-check-maven:check versions:set -DnewVersion=$LOGHI_VERSION clean package \
RUN cd /src/loghi-tooling \
  && mvn versions:set -DgenerateBackupPoms=false -DnewVersion=$LOGHI_VERSION clean package \
  && find . -name src | xargs rm -rf \
  && find . -name test-classes | xargs rm -rf \
  && rm -rf /src/loghi-tooling/layoutanalyzer/target \
  && apt-get remove -y maven && apt autoremove -y \
  && rm -rf /var/lib/apt \
  && rm -rf /home/root \
  && rm -rf /root
