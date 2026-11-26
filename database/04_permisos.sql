BEGIN;

GRANT SELECT, INSERT, UPDATE
ON TABLE
    public.compras,
    public.compra_detalles,
    public.pagos,
    public.compra_eventos_outbox
TO service_role;

GRANT SELECT, UPDATE
ON TABLE public.products
TO service_role;

GRANT SELECT, INSERT
ON TABLE public.boletas
TO service_role;

GRANT USAGE, SELECT
ON SEQUENCE public.compra_detalles_id_seq
TO service_role;

GRANT EXECUTE
ON FUNCTION public.validar_compra(UUID)
TO service_role;

GRANT EXECUTE
ON FUNCTION public.procesar_pago(UUID)
TO service_role;

COMMIT;