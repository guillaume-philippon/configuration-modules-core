# ${license-info}
# ${developer-info}
# ${author-info}
# ${build-info}

declaration template components/${project.artifactId}/schema;

include { 'quattor/schema' };

type ${project.artifactId}_livestatus = {
    'enable' : boolean = true
    'port' : int : 6557
};

type ${project.artifactId}_config = {
    'default_gui' : string = 'check_mk'
    'livestatus' ? ${project.artifactId}_livestatus
    'crontab' : boolean = true
} = nlist();

type ${project.artifactId}_hosts = {
    'tags' : string[] = list()
} = nlist();

type ${project.artifactId}_sites = {
    'config' : ${project.artifactId}_config
    'hosts' : ${project.artifactId}_hosts{}
} = nlist();

type ${project.artifactId}_component = {
    include structure_component
    'sites' : ${project.artifactId}_sites{} ?= nlist()
};

bind '/software/components/${project.artifactId}' = ${project.artifactId}_component;
