from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import Lambda
from diagrams.aws.database import Dynamodb
from diagrams.aws.network import APIGateway
from diagrams.aws.security import SecretsManager
from diagrams.onprem.client import Users
from diagrams.aws.general import General

graph_attr = {
    "fontsize": "13",
    "bgcolor": "white",
    "pad": "0.6",
    "splines": "ortho",
    "nodesep": "0.9",
    "ranksep": "1.2",
}

with Diagram(
    "Multi-Agent Coding Orchestrator",
    filename="docs/architecture",
    outformat="png",
    show=False,
    direction="LR",
    graph_attr=graph_attr,
):
    client = Users("Client")
    anthropic = General("Anthropic API")

    with Cluster("AWS"):
        apigw = APIGateway("API Gateway\nHTTP API")

        with Cluster("Authorizer"):
            auth = Lambda("auth\n(x-api-key)")

        with Cluster("Lambdas"):
            orchestrator = Lambda("orchestrator\nPOST /task")
            status_fn = Lambda("status\nGET /status/{id}")
            coder = Lambda("coder\n(async)")

        jobs_db = Dynamodb("jobs\nDynamoDB TTL")
        secret = SecretsManager("anthropic-api-key\nSecrets Manager")

    # Request flow
    client >> apigw
    apigw >> Edge(label="authorize", style="dashed", color="gray") >> auth
    apigw >> orchestrator
    apigw >> status_fn

    # Orchestrator flow
    orchestrator >> Edge(label="create job") >> jobs_db
    orchestrator >> Edge(label="async invoke") >> coder

    # Coder flow
    coder >> Edge(label="get key") >> secret
    coder >> Edge(label="LLM calls") >> anthropic
    coder >> Edge(label="update result") >> jobs_db

    # Status flow
    status_fn >> Edge(label="get item") >> jobs_db
