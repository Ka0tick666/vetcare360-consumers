BEGIN;

CREATE TABLE public.compras (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cliente_id TEXT NOT NULL,
    total NUMERIC(14,2) NOT NULL CHECK (total > 0),
    moneda TEXT NOT NULL DEFAULT 'CLP'
        CHECK (moneda = 'CLP'),
    estado TEXT NOT NULL DEFAULT 'PENDIENTE'
        CHECK (estado IN (
            'PENDIENTE',
            'VALIDADA',
            'RECHAZADA',
            'PAGADA'
        )),
    motivo_rechazo TEXT,
    simulacion BOOLEAN NOT NULL DEFAULT TRUE
        CHECK (simulacion = TRUE),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.compra_detalles (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    compra_id UUID NOT NULL REFERENCES public.compras(id),
    producto_id BIGINT NOT NULL REFERENCES public.products(id),
    nombre_producto TEXT NOT NULL,
    cantidad INTEGER NOT NULL CHECK (cantidad > 0),
    precio_unitario NUMERIC(14,2) NOT NULL
        CHECK (precio_unitario > 0),
    subtotal NUMERIC(14,2)
        GENERATED ALWAYS AS (
            cantidad::NUMERIC * precio_unitario
        ) STORED,
    UNIQUE (compra_id, producto_id)
);

CREATE TABLE public.pagos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    compra_id UUID NOT NULL UNIQUE
        REFERENCES public.compras(id),
    monto NUMERIC(14,2) NOT NULL CHECK (monto > 0),
    moneda TEXT NOT NULL DEFAULT 'CLP'
        CHECK (moneda = 'CLP'),
    metodo TEXT NOT NULL DEFAULT 'SIMULADO'
        CHECK (metodo = 'SIMULADO'),
    estado TEXT NOT NULL
        CHECK (estado IN ('APROBADO', 'RECHAZADO')),
    event_id TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.compra_eventos_outbox (
    event_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    compra_id UUID NOT NULL REFERENCES public.compras(id),
    tipo TEXT NOT NULL CHECK (
        tipo IN (
            'compra.creada',
            'compra.validada',
            'compra.rechazada',
            'compra.pagada'
        )
    ),
    payload JSONB NOT NULL,
    publicado BOOLEAN NOT NULL DEFAULT FALSE,
    intentos INTEGER NOT NULL DEFAULT 0
        CHECK (intentos >= 0),
    ultimo_error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    publicado_at TIMESTAMPTZ,
    UNIQUE (compra_id, tipo)
);

CREATE INDEX idx_compras_cliente
ON public.compras (cliente_id, created_at DESC);

CREATE INDEX idx_compras_estado
ON public.compras (estado);

CREATE INDEX idx_compra_detalles_producto
ON public.compra_detalles (producto_id);

CREATE INDEX idx_outbox_pendientes
ON public.compra_eventos_outbox (created_at)
WHERE publicado = FALSE;

ALTER TABLE public.compras
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.compra_detalles
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.pagos
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.compra_eventos_outbox
ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE
    public.compras,
    public.compra_detalles,
    public.pagos,
    public.compra_eventos_outbox
FROM PUBLIC, anon, authenticated;

COMMIT;