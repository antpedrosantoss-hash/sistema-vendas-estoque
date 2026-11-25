import os
import json
from decimal import Decimal
from flask import Flask, render_template, request, redirect, url_for, flash
import psycopg2
from dotenv import load_dotenv
from psycopg2.extras import RealDictCursor

load_dotenv()

app = Flask(__name__)
app.secret_key = os.getenv("SECRET_KEY", "troque-esta-chave")

def conectar():
    return psycopg2.connect(
        os.getenv("DATABASE_URL",
                  "postgresql://postgres:senha@localhost:5432/vendas_estoque"),
        cursor_factory=RealDictCursor
    )

@app.route("/")
def index():
    with conectar() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) AS total FROM produtos")
            produtos = cur.fetchone()["total"]
            cur.execute("SELECT COUNT(*) AS total FROM clientes")
            clientes = cur.fetchone()["total"]
            cur.execute("SELECT COUNT(*) AS total FROM vendas")
            vendas = cur.fetchone()["total"]
            cur.execute("""
                SELECT v.id, c.nome AS cliente, v.data_venda, v.total
                FROM vendas v JOIN clientes c ON c.id = v.cliente_id
                ORDER BY v.id DESC LIMIT 8
            """)
            ultimas = cur.fetchall()
    return render_template("index.html", produtos=produtos, clientes=clientes,
                           vendas=vendas, ultimas=ultimas)

@app.route("/produtos", methods=["GET", "POST"])
def produtos():
    if request.method == "POST":
        nome = request.form["nome"].strip()
        preco = request.form["preco"]
        estoque = request.form["estoque"]
        if not nome:
            flash("Informe o nome do produto.", "erro")
        else:
            with conectar() as conn:
                with conn.cursor() as cur:
                    cur.execute(
                        "INSERT INTO produtos (nome, preco, estoque) VALUES (%s, %s, %s)",
                        (nome, preco, estoque)
                    )
            flash("Produto cadastrado.", "sucesso")
        return redirect(url_for("produtos"))

    with conectar() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM produtos ORDER BY id")
            lista = cur.fetchall()
    return render_template("produtos.html", produtos=lista)

@app.route("/produtos/<int:id>/editar", methods=["POST"])
def editar_produto(id):
    with conectar() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE produtos SET nome=%s, preco=%s, estoque=%s
                WHERE id=%s
            """, (request.form["nome"], request.form["preco"],
                  request.form["estoque"], id))
    flash("Produto atualizado.", "sucesso")
    return redirect(url_for("produtos"))

@app.route("/produtos/<int:id>/excluir", methods=["POST"])
def excluir_produto(id):
    try:
        with conectar() as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM produtos WHERE id=%s", (id,))
        flash("Produto excluído.", "sucesso")
    except psycopg2.Error:
        flash("Não foi possível excluir: o produto pode estar vinculado a uma venda.", "erro")
    return redirect(url_for("produtos"))

@app.route("/clientes", methods=["GET", "POST"])
def clientes():
    if request.method == "POST":
        nome = request.form["nome"].strip()
        email = request.form.get("email", "").strip() or None
        with conectar() as conn:
            with conn.cursor() as cur:
                cur.execute("INSERT INTO clientes (nome, email) VALUES (%s, %s)", (nome, email))
        flash("Cliente cadastrado.", "sucesso")
        return redirect(url_for("clientes"))
    with conectar() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM clientes ORDER BY id")
            lista = cur.fetchall()
    return render_template("clientes.html", clientes=lista)

@app.route("/clientes/<int:id>/editar", methods=["POST"])
def editar_cliente(id):
    with conectar() as conn:
        with conn.cursor() as cur:
            cur.execute("UPDATE clientes SET nome=%s, email=%s WHERE id=%s",
                        (request.form["nome"], request.form.get("email") or None, id))
    flash("Cliente atualizado.", "sucesso")
    return redirect(url_for("clientes"))

@app.route("/clientes/<int:id>/excluir", methods=["POST"])
def excluir_cliente(id):
    try:
        with conectar() as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM clientes WHERE id=%s", (id,))
        flash("Cliente excluído.", "sucesso")
    except psycopg2.Error:
        flash("Não foi possível excluir: o cliente possui vendas registradas.", "erro")
    return redirect(url_for("clientes"))

@app.route("/vendas", methods=["GET", "POST"])
def vendas():
    if request.method == "POST":
        cliente_id = int(request.form["cliente_id"])
        ids = request.form.getlist("produto_id")
        quantidades = request.form.getlist("quantidade")
        itens = []
        for pid, qtd in zip(ids, quantidades):
            if pid and qtd and int(qtd) > 0:
                itens.append({"produto_id": int(pid), "quantidade": int(qtd)})
        if not itens:
            flash("Adicione pelo menos um item à venda.", "erro")
            return redirect(url_for("vendas"))
        try:
            # A procedure controla a confirmação/rollback da operação.
            conn = conectar()
            conn.autocommit = True
            with conn.cursor() as cur:
                cur.execute("CALL registrar_venda(%s, %s::jsonb)",
                            (cliente_id, json.dumps(itens)))
            conn.close()
            flash("Venda realizada com sucesso.", "sucesso")
        except Exception as exc:
            flash(f"Venda não realizada: {exc}", "erro")
        return redirect(url_for("vendas"))

    with conectar() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT id, nome FROM clientes ORDER BY nome")
            clientes_lista = cur.fetchall()
            cur.execute("SELECT id, nome, preco, estoque FROM produtos WHERE estoque > 0 ORDER BY nome")
            produtos_lista = cur.fetchall()
            cur.execute("""
                SELECT v.id, c.nome AS cliente, v.data_venda, v.total
                FROM vendas v JOIN clientes c ON c.id=v.cliente_id
                ORDER BY v.id DESC
            """)
            vendas_lista = cur.fetchall()
    return render_template("vendas.html", clientes=clientes_lista,
                           produtos=produtos_lista, vendas=vendas_lista)

@app.route("/vendas/<int:id>")
def detalhe_venda(id):
    with conectar() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT v.id, c.nome AS cliente, v.data_venda, v.total
                FROM vendas v JOIN clientes c ON c.id=v.cliente_id WHERE v.id=%s
            """, (id,))
            venda = cur.fetchone()
            cur.execute("""
                SELECT p.nome, i.quantidade, i.preco_unitario,
                       i.quantidade * i.preco_unitario AS subtotal
                FROM itens_venda i JOIN produtos p ON p.id=i.produto_id
                WHERE i.venda_id=%s ORDER BY p.nome
            """, (id,))
            itens = cur.fetchall()
    if not venda:
        flash("Venda não encontrada.", "erro")
        return redirect(url_for("vendas"))
    return render_template("detalhe_venda.html", venda=venda, itens=itens)

if __name__ == "__main__":
    app.run(debug=True)
