#!/bin/bash

set -e
tmp_dir=$(mktemp -d)
container_id=$(docker run -u $(id -u ${USER}):$(id -g ${USER}) \
    -v $tmp_dir:/tmp/upload \
    --name tooling_integrationtest \
    -d -p 8080:8080 -p 8081:8081 \
    loghi/docker.loghi-tooling \
        /src/loghi-tooling/loghiwebservice/target/appassembler/bin/LoghiWebserviceApplication \
        server \
        /src/loghi-tooling/loghiwebservice/target/classes/configuration.yml)
echo $container_id

while [ "$( docker container inspect -f '{{.State.Status}}' tooling_integrationtest )" != "running" ]; do
	echo waiting for the docker to start
	sleep 5s
done

while [ "$(curl -s -o /dev/null -w "%{http_code}" localhost:8081/prometheus)" != "200" ]; do
	echo waiting for webservice to start
	sleep 5s
done

cd ../loghi-tooling/loghiwebservice/src/test/resources/integration_tests/

echo "Cutting image based on PageXML"
echo "--------------------------------"
bash test_cut_based_on_page_xml.sh $tmp_dir
echo "Detecting language"
echo "--------------------------------"
bash test_detect_language.sh $tmp_dir
echo "Extracting baselines"
echo "--------------------------------"
bash test_extract_baselines.sh $tmp_dir
echo "Merging PageXML"
echo "--------------------------------"
bash test_loghi_htr_merge_page_xml.sh $tmp_dir
echo "Recalculate reading order"
echo "--------------------------------"
bash test_recalculate_reading_order.sh $tmp_dir
echo "Split text lines into words"
echo "--------------------------------"
bash test_split_text_lines_into_words.sh $tmp_dir

docker stop $container_id
docker rm $container_id
