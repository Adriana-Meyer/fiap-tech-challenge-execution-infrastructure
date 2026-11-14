# fiap-tech-challenge-execution-infrastructure

Infraestrutura do **Execution Service** (fila de execução dos serviços da oficina) do Tech Challenge — FIAP Pós-Tech, Arquitetura de Software, turma 15SOAT, **Fase 4** (microsserviços + Saga). Provisiona, via Terraform, o que o serviço precisa no cluster e na AWS **exceto o banco**: o namespace Kubernetes com a cota de recursos, e a fila SQS de comandos com a sua DLQ.

| Repositório | Papel |
|---|---|
| [`fiap-tech-challenge-execution-service`](https://github.com/Adriana-Meyer/fiap-tech-challenge-execution-service) | Código do serviço |
| **fiap-tech-challenge-execution-infrastructure** (este) | Namespace `execution`, ResourceQuota e fila `execution-commands` (+ DLQ) |
| `fiap-tech-challenge-execution-database-infrastructure` | Tabela DynamoDB `execution-orders` do serviço |
| [`fiap-tech-challenge-os-infrastructure`](https://github.com/Adriana-Meyer/fiap-tech-challenge-os-infrastructure) | VPC, cluster EKS, New Relic e a mensageria compartilhada da saga (tópico `saga-events`) |

## O que este repositório cria

| Recurso | Detalhe |
|---|---|
| Namespace `execution` | onde o serviço é implantado (`kubectl apply` do `deploy-aws.yml` do serviço) |
| ResourceQuota `execution-quota` | teto de CPU, memória, pods e load balancers do namespace |
| Fila SQS `execution-commands` | recebe os comandos do OS: `EnqueueExecution` |
| Fila SQS `execution-commands-dlq` | recebe o comando que falhou depois de 3 tentativas |

As respostas do Execution seguem o caminho inverso, pelo tópico `saga-events`, que pertence ao `os-infrastructure`.

## Tecnologias

| Camada | Tecnologia |
|---|---|
| Provisionamento | Terraform >= 1.5, providers `hashicorp/aws` e `hashicorp/kubernetes` |
| Nuvem | AWS (AWS Academy Learner Lab): SQS e EKS |
| CI/CD | GitHub Actions |

## Decisões de desenho

- **O cluster é descoberto pelo nome fixo** (`tech-challenge-eks`), por `data source`, como o `os-database-infrastructure` já faz com a rede: sem copiar endpoint nem credencial entre repositórios e sem acoplar ao estado de outro repo. Por isso o `os-infrastructure` precisa ter sido aplicado antes, na mesma sessão do Lab.
- **Os nomes são fixos e sem prefixo de projeto** (`execution`, `execution-commands`): o OS envia para `execution-commands` e o serviço escuta nessa fila por padrão (`COMMANDS_QUEUE`). O namespace também é o que os manifests do serviço (`k8s/`) esperam. A variável `service_name` existe para os três repositórios de infraestrutura de serviço terem o mesmo código, e só deve ser alterada junto com o serviço.
- **ResourceQuota dimensionada a partir dos manifests reais.** O serviço roda de 1 a 2 réplicas (HPA), cada uma pedindo `250m` de CPU e `256Mi` de memória, com limites de `500m` e `512Mi`. O rolling update sobe um terceiro pod por instantes, então os tetos cobrem 3 pods com folga:

  | Recurso | Teto | Uso no pior caso (3 pods) |
  |---|---|---|
  | `requests.cpu` / `requests.memory` | `1` / `1Gi` | `750m` / `768Mi` |
  | `limits.cpu` / `limits.memory` | `2` / `2Gi` | `1500m` / `1536Mi` |
  | `pods` | `6` | 3 |
  | `services.loadbalancers` | `1` | 1 |

  A cota evita que um serviço consuma os poucos nós do cluster e limita a **um** o número de load balancers: cada serviço tem o seu NLB, e um `Service` do tipo `LoadBalancer` esquecido continuaria gerando custo depois da sessão do Lab. **Todo pod do namespace precisa declarar requests e limits**, senão a cota o rejeita (os manifests do serviço já declaram).
- **DLQ com retenção de 14 dias** (o máximo do SQS) e **3 tentativas** antes de mover a mensagem para ela: dá tempo de inspecionar um comando que falhou. A visibilidade de 30 s deve ser maior que o tratamento mais lento de um comando; os handlers são idempotentes, então uma entrega repetida não causa dano.
- Criptografia em repouso com SSE gerenciado pelo SQS.
- **Sem RDS:** o Execution guarda os dados no DynamoDB; a tabela é criada pelo `execution-database-infrastructure` e o acesso dos pods é pelo role do nó (não há secret de banco). Este repositório não depende dela para subir, mas o serviço precisa da tabela para funcionar.
- **O serviço não cria filas:** se `execution-commands` não existir ele falha na subida (de propósito, para denunciar este repositório não aplicado em vez de criar uma fila sem DLQ).

## Pré-requisitos

- Terraform >= 1.5
- Conta AWS Academy Learner Lab **ativa**, com credenciais temporárias exportadas
- `os-infrastructure` já aplicado na mesma sessão (o cluster precisa existir)

## Executando

```bash
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...

terraform init
terraform plan
terraform apply
```

Ordem de uso numa sessão do Lab:

- **Subir:** `os-infrastructure` → **este repositório** → `execution-database-infrastructure` → deploy do `execution-service`.
- **Desligar:** `destroy` do `execution-service` (que libera o load balancer) → `execution-database-infrastructure` → **este repositório** → `os-infrastructure`. Destruir este repositório antes apagaria o namespace com o `Service` ainda dentro, e o load balancer poderia ficar para trás.

## CI/CD

- **`terraform-validate.yml`** — em todo push/PR para `develop`/`main`: `terraform fmt -check`, `terraform init -backend=false`, `terraform validate`. Não precisa de credenciais AWS.
- **`terraform-apply.yml`** — disparo manual (`workflow_dispatch`) com escolha entre `plan`, `apply` e `destroy`. Usa as credenciais temporárias da sessão do Lab, guardadas nos secrets `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` e `AWS_SESSION_TOKEN` (precisam ser renovados a cada sessão, ~4 h). Fica manual de propósito, para não gastar o orçamento do Lab a cada merge; o `apply` em si é automático de ponta a ponta quando disparado.

## Variáveis Terraform

Todas têm valor padrão (ver [`variables.tf`](variables.tf)):

| Variável | Padrão | Descrição |
|---|---|---|
| `eks_cluster_name` | `tech-challenge-eks` | Nome fixo do cluster criado pelo `os-infrastructure` |
| `service_name` | `execution` | Nome do serviço: namespace e prefixo da fila |
| `resource_quota` | ver acima | Tetos do namespace |
| `max_receive_count` | `3` | Tentativas antes de ir para a DLQ |
| `queue_visibility_timeout_seconds` | `30` | Tempo que o comando em tratamento fica oculto |

## Como foi validado

Além de `fmt` e `validate` (CI), a configuração inteira foi aplicada e destruída fora da AWS: a fila num LocalStack e o namespace com a cota num cluster `kind` descartável. Com isso foram conferidos:

- o `apply` cria os 4 recursos e o `plan` seguinte não mostra diferenças; o `destroy` apaga tudo;
- os **manifests reais do serviço** (`k8s/`) cabem na cota: com 2 réplicas e um rolling update o pico é de 3 pods, dentro dos tetos e sem rejeição;
- a cota rejeita um pod sem requests/limits, um pod que passaria do teto de memória e um segundo `Service` do tipo `LoadBalancer`;
- um comando recebido 3 vezes sem ser apagado vai para a DLQ com o corpo intacto.

O `apply` contra a AWS real depende das credenciais do Lab e é feito na fase de validação no Lab.

## APIs

Este repositório não expõe API própria — é infraestrutura de plataforma. A API do serviço está no [execution-service](https://github.com/Adriana-Meyer/fiap-tech-challenge-execution-service).
