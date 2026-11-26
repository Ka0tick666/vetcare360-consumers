BEGIN;

CREATE OR REPLACE FUNCTION public.validar_compra(
    p_compra_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO ''
AS $function$
DECLARE
    v_compra public.compras%ROWTYPE;
    v_total NUMERIC;
    v_motivo TEXT;
    v_estado TEXT;
    v_tipo TEXT;
    v_event_id UUID;
BEGIN
    SELECT *
    INTO v_compra
    FROM public.compras
    WHERE id = p_compra_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Compra no encontrada';
    END IF;

    IF v_compra.estado <> 'PENDIENTE' THEN
        RETURN jsonb_build_object(
            'success', TRUE,
            'duplicate', TRUE,
            'compra_id', p_compra_id,
            'estado', v_compra.estado
        );
    END IF;

    SELECT COALESCE(SUM(subtotal), 0)
    INTO v_total
    FROM public.compra_detalles
    WHERE compra_id = p_compra_id;

    IF v_total <= 0 THEN
        v_motivo := 'La compra no contiene productos';

    ELSIF v_total <> v_compra.total THEN
        v_motivo := 'El total de la compra no coincide';

    ELSIF EXISTS (
        SELECT 1
        FROM public.compra_detalles d
        JOIN public.products p
            ON p.id = d.producto_id
        WHERE d.compra_id = p_compra_id
          AND p.stock < d.cantidad
    ) THEN
        v_motivo := 'Stock insuficiente';

    ELSIF EXISTS (
        SELECT 1
        FROM public.compra_detalles d
        JOIN public.products p
            ON p.id = d.producto_id
        WHERE d.compra_id = p_compra_id
          AND ROUND(p.price::NUMERIC, 2)
              <> d.precio_unitario
    ) THEN
        v_motivo := 'El precio del producto ha cambiado';
    END IF;

    IF v_motivo IS NULL THEN
        v_estado := 'VALIDADA';
        v_tipo := 'compra.validada';
    ELSE
        v_estado := 'RECHAZADA';
        v_tipo := 'compra.rechazada';
    END IF;

    UPDATE public.compras
    SET estado = v_estado,
        motivo_rechazo = v_motivo,
        updated_at = now()
    WHERE id = p_compra_id;

    v_event_id := gen_random_uuid();

    INSERT INTO public.compra_eventos_outbox (
        event_id,
        compra_id,
        tipo,
        payload
    )
    VALUES (
        v_event_id,
        p_compra_id,
        v_tipo,
        jsonb_build_object(
            'event_id', v_event_id,
            'type', v_tipo,
            'compra_id', p_compra_id,
            'cliente_id', v_compra.cliente_id,
            'total', v_compra.total,
            'moneda', v_compra.moneda,
            'estado', v_estado,
            'motivo', v_motivo,
            'simulacion', TRUE
        )
    );

    RETURN jsonb_build_object(
        'success', TRUE,
        'duplicate', FALSE,
        'compra_id', p_compra_id,
        'estado', v_estado,
        'event_id', v_event_id,
        'motivo', v_motivo
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.validar_compra(UUID)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.validar_compra(UUID)
TO service_role;

COMMIT;