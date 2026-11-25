# Sistema de Vendas e Controle de Estoque

Projeto acadêmico de Banco de Dados II — IFPI Campus Picos. Aplicação web em Flask integrada ao PostgreSQL, com operações CRUD, Function, Trigger e Procedure.

## Tecnologias
- Python 3.10 ou superior
- Flask
- PostgreSQL
- psycopg2
- python-dotenv

## Estrutura
- `app.py`: aplicação Flask e rotas.
- `database.sql`: criação das tabelas, relacionamentos, dados de exemplo e recursos do PostgreSQL.
- `templates/`: páginas HTML.
- `DER.md`: diagrama entidade-relacionamento.
- `SEMINARIO.md`: roteiro de apresentação e perguntas para revisão.
- `.env.example`: modelo das variáveis de ambiente.

## 1. Preparar o banco de dados
1. Crie no PostgreSQL um banco chamado `vendas_estoque`.
2. Abra esse banco no pgAdmin ou em outro cliente SQL.
3. Execute o conteúdo de `database.sql`.

> **Atenção:** o script começa removendo tabelas existentes (`DROP TABLE ... CASCADE`) para recriar a estrutura. Execute-o somente em um banco de desenvolvimento/teste sem dados que você queira preservar. Executá-lo novamente apaga os dados dessas tabelas.

## 2. Configurar a aplicação
No terminal, dentro da pasta do projeto, crie e ative um ambiente virtual:

```bash
python -m venv .venv
```

No Windows:
```powershell
.venv\Scripts\Activate.ps1
```

No Linux/macOS:
```bash
source .venv/bin/activate
```

Instale as dependências:
```bash
pip install -r requirements.txt
```

Copie `.env.example` para um arquivo chamado `.env` e ajuste os valores para seu PostgreSQL:

```env
DATABASE_URL=postgresql://USUARIO:SENHA@localhost:5432/vendas_estoque
SECRET_KEY=uma-chave-aleatoria
```

Não publique o arquivo `.env` nem compartilhe sua senha. O `.gitignore` já está configurado para ignorá-lo.

## 3. Executar

```bash
python app.py
```

Acesse no navegador: http://127.0.0.1:5000

## Funcionalidades
- Dashboard com resumo de produtos, clientes e vendas.
- Cadastro, consulta, edição e exclusão de produtos.
- Cadastro, consulta, edição e exclusão de clientes.
- Registro de venda com vários produtos.
- Histórico e detalhes das vendas.
- Baixa automática do estoque e registro de movimentações.
- Bloqueio de vendas com quantidade superior ao estoque disponível.

## Recursos do PostgreSQL demonstrados
- **Function `calcular_total_venda`:** calcula e retorna o total de uma venda.
- **Trigger `trg_baixar_estoque`:** antes da inserção de cada item, valida o estoque, atualiza a quantidade e registra a movimentação.
- **Procedure `registrar_venda`:** coordena a criação da venda e dos itens, calcula o total e confirma ou desfaz a operação em caso de erro.

O roteiro detalhado para demonstrar esses recursos está em `SEMINARIO.md`.

## Publicar no GitHub
Depois de criar um repositório vazio no GitHub, execute na pasta do projeto (substitua a URL pela URL do seu repositório):

```bash
git init
git add .
git commit -m "Sistema de vendas e controle de estoque"
git branch -M main
git remote add origin https://github.com/SEU-USUARIO/sistema-vendas-estoque.git
git push -u origin main
```

## Integrantes
Preencha aqui os nomes dos integrantes da equipe antes da entrega.
