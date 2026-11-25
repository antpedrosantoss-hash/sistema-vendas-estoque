-- SISTEMA DE VENDAS E CONTROLE DE ESTOQUE
-- Execute este arquivo conectado ao banco vendas_estoque.

DROP TABLE IF EXISTS movimentacoes_estoque CASCADE;
DROP TABLE IF EXISTS itens_venda CASCADE;
DROP TABLE IF EXISTS vendas CASCADE;
DROP TABLE IF EXISTS produtos CASCADE;
DROP TABLE IF EXISTS clientes CASCADE;

CREATE TABLE clientes (
    id BIGSERIAL PRIMARY KEY,
    nome VARCHAR(120) NOT NULL,
    email VARCHAR(160) UNIQUE,
    criado_em TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE produtos (
    id BIGSERIAL PRIMARY KEY,
    nome VARCHAR(120) NOT NULL,
    preco NUMERIC(12,2) NOT NULL CHECK (preco >= 0),
    estoque INTEGER NOT NULL DEFAULT 0 CHECK (estoque >= 0),
    criado_em TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE vendas (
    id BIGSERIAL PRIMARY KEY,
    cliente_id BIGINT NOT NULL REFERENCES clientes(id),
    data_venda TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    total NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (total >= 0)
);

CREATE TABLE itens_venda (
    id BIGSERIAL PRIMARY KEY,
    venda_id BIGINT NOT NULL REFERENCES vendas(id) ON DELETE CASCADE,
    produto_id BIGINT NOT NULL REFERENCES produtos(id),
    quantidade INTEGER NOT NULL CHECK (quantidade > 0),
    preco_unitario NUMERIC(12,2) NOT NULL CHECK (preco_unitario >= 0)
);

CREATE TABLE movimentacoes_estoque (
    id BIGSERIAL PRIMARY KEY,
    produto_id BIGINT NOT NULL REFERENCES produtos(id),
    tipo VARCHAR(20) NOT NULL CHECK (tipo IN ('SAIDA_VENDA')),
    quantidade INTEGER NOT NULL CHECK (quantidade > 0),
    observacao TEXT,
    data_movimentacao TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- FUNCTION: calcula o total de uma venda (retorna um valor escalar).
CREATE OR REPLACE FUNCTION calcular_total_venda(p_venda_id BIGINT)
RETURNS NUMERIC(12,2)
LANGUAGE SQL
STABLE
AS $$
    SELECT COALESCE(SUM(quantidade * preco_unitario), 0)::NUMERIC(12,2)
    FROM itens_venda
    WHERE venda_id = p_venda_id;
$$;

-- TRIGGER FUNCTION: valida e reduz estoque e registra a movimentação.
CREATE OR REPLACE FUNCTION fn_baixar_estoque_venda()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_estoque INTEGER;
    v_nome VARCHAR(120);
BEGIN
    SELECT estoque, nome INTO v_estoque, v_nome
    FROM produtos
    WHERE id = NEW.produto_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Produto % não encontrado.', NEW.produto_id;
    END IF;

    IF v_estoque < NEW.quantidade THEN
        RAISE EXCEPTION 'Estoque insuficiente para "%". Disponível: %, solicitado: %.',
            v_nome, v_estoque, NEW.quantidade;
    END IF;

    UPDATE produtos
       SET estoque = estoque - NEW.quantidade
     WHERE id = NEW.produto_id;

    INSERT INTO movimentacoes_estoque(produto_id, tipo, quantidade, observacao)
    VALUES (NEW.produto_id, 'SAIDA_VENDA', NEW.quantidade,
            'Baixa automática pela venda ' || NEW.venda_id);

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_baixar_estoque
BEFORE INSERT ON itens_venda
FOR EACH ROW
EXECUTE FUNCTION fn_baixar_estoque_venda();

-- PROCEDURE: realiza todos os passos da venda.
-- A aplicação chama esta procedure com autocommit habilitado.
-- Se algum item falhar, o bloco interno desfaz os passos da venda;
-- caso tudo funcione, a procedure confirma com COMMIT.
CREATE OR REPLACE PROCEDURE registrar_venda(
    p_cliente_id BIGINT,
    p_itens JSONB
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_venda_id BIGINT;
    v_item JSONB;
    v_produto_id BIGINT;
    v_quantidade INTEGER;
    v_preco NUMERIC(12,2);
    v_erro TEXT;
BEGIN
    IF p_itens IS NULL OR jsonb_typeof(p_itens) <> 'array'
       OR jsonb_array_length(p_itens) = 0 THEN
        RAISE EXCEPTION 'A venda precisa conter pelo menos um item.';
    END IF;

    -- O bloco interno é uma subtransação: em caso de erro,
    -- todas as alterações feitas dentro dele são revertidas.
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM clientes WHERE id = p_cliente_id) THEN
            RAISE EXCEPTION 'Cliente não encontrado.';
        END IF;

        INSERT INTO vendas(cliente_id, total)
        VALUES (p_cliente_id, 0)
        RETURNING id INTO v_venda_id;

        FOR v_item IN SELECT value FROM jsonb_array_elements(p_itens)
        LOOP
            v_produto_id := (v_item->>'produto_id')::BIGINT;
            v_quantidade := (v_item->>'quantidade')::INTEGER;

            IF v_quantidade IS NULL OR v_quantidade <= 0 THEN
                RAISE EXCEPTION 'A quantidade deve ser maior que zero.';
            END IF;

            SELECT preco INTO v_preco
            FROM produtos
            WHERE id = v_produto_id;

            IF NOT FOUND THEN
                RAISE EXCEPTION 'Produto % não encontrado.', v_produto_id;
            END IF;

            INSERT INTO itens_venda(venda_id, produto_id, quantidade, preco_unitario)
            VALUES (v_venda_id, v_produto_id, v_quantidade, v_preco);
            -- O INSERT dispara o trigger que valida e baixa o estoque.
        END LOOP;

        UPDATE vendas
           SET total = calcular_total_venda(v_venda_id)
         WHERE id = v_venda_id;

    EXCEPTION WHEN OTHERS THEN
        v_erro := SQLERRM;
    END;

    IF v_erro IS NOT NULL THEN
        ROLLBACK;
        RAISE EXCEPTION 'Venda cancelada; alterações desfeitas. Motivo: %', v_erro;
    ELSE
        COMMIT;
    END IF;
END;
$$;

-- DADOS INICIAIS PARA TESTE
INSERT INTO clientes(nome, email) VALUES
('Ana Souza', 'ana@email.com'),
('Carlos Lima', 'carlos@email.com');

INSERT INTO produtos(nome, preco, estoque) VALUES
('Teclado', 85.90, 15),
('Mouse', 49.90, 20),
('Monitor', 799.00, 8);

-- CONSULTAS DE TESTE:
-- SELECT * FROM produtos;
-- SELECT calcular_total_venda(1);
-- CALL registrar_venda(1, '[{"produto_id":1,"quantidade":2},{"produto_id":2,"quantidade":1}]');
-- SELECT * FROM vendas;
-- SELECT * FROM movimentacoes_estoque;
