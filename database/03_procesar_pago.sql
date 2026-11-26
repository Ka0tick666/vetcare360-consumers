BEGIN;

CREATE OR REPLACE FUNCTION public.procesar_pago(
    p_compra_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO ''
AS $function$
DECLARE
    v_compra public.compras%ROWTYPE;
    v_pago_id UUID;
    v_event_id UUID;
    v_estado TEXT;
    v_tipo TEXT;
    v_motivo TEXT;
    v_items JSONB;
BEGIN
    SELECT *
    INTO v_compra
    FROM public.compras
    WHERE id = p_compra_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Compra no encontrada';
    END IF;

    IF v_compra.estado IN ('PAGADA', 'RECHAZADA') THEN
        RETURN jsonb_build_object(
            'success', TRUE,
            'duplicate', TRUE,
            'compra_id', p_compra_id,
            'estado', v_compra.estado
        );
    END IF;

    IF v_compra.estado <> 'VALIDADA' THEN
        RAISE EXCEPTION 'La compra no esta validada';
    END IF;

    -- Bloquear productos en orden.

    PERFORM p.id
    FROM public.products p
    JOIN public.compra_detalles d
        ON d.producto_id = p.id
    WHERE d.compra_id = p_compra_id
    ORDER BY p.id
    FOR UPDATE OF p;

    -- Comprobar nuevamente la disponibilidad.

    IF EXISTS (
        SELECT 1
        FROM public.compra_detalles d
        JOIN public.products p
            ON p.id = d.producto_id
        WHERE d.compra_id = p_compra_id
          AND p.stock < d.cantidad
    ) THEN
        v_motivo := 'Stock insuficiente al procesar pago';
    END IF;

    v_event_id := gen_random_uuid();

    IF v_motivo IS NOT NULL THEN

        v_estado := 'RECHAZADA';
        v_tipo := 'compra.rechazada';

        INSERT INTO public.pagos (
            compra_id,
            monto,
            moneda,
            metodo,
            estado,
            event_id
        )
        VALUES (
            p_compra_id,
            v_compra.total,
            v_compra.moneda,
            'SIMULADO',
            'RECHAZADO',
            v_event_id::TEXT
        )
        RETURNING id INTO v_pago_id;

    ELSE

        v_estado := 'PAGADA';
        v_tipo := 'compra.pagada';

        INSERT INTO public.pagos (
            compra_id,
            monto,
            moneda,
            metodo,
            estado,
            event_id
        )
        VALUES (
            p_compra_id,
            v_compra.total,
            v_compra.moneda,
            'SIMULADO',
            'APROBADO',
            v_event_id::TEXT
        )
        RETURNING id INTO v_pago_id;

        -- Descontar stock.

        UPDATE public.products p
        SET stock = p.stock - d.cantidad
        FROM public.compra_detalles d
        WHERE d.compra_id = p_compra_id
          AND p.id = d.producto_id;

        -- Construir detalle de la boleta.

        SELECT jsonb_agg(
            jsonb_build_object(
                'id', producto_id,
                'nombre', nombre_producto,
                'cantidad', cantidad,
                'precio', precio_unitario,
                'subtotal', subtotal
            )
            ORDER BY producto_id
        )
        INTO v_items
        FROM public.compra_detalles
        WHERE compra_id = p_compra_id;

        INSERT INTO public.boletas (
            id,
            fecha,
            cliente,
            items,
            total
        )
        VALUES (
            p_compra_id::TEXT,
            now()::TEXT,
            v_compra.cliente_id,
            v_items,
            v_compra.total::DOUBLE PRECISION
        );

    END IF;

    UPDATE public.compras
    SET estado = v_estado,
        motivo_rechazo = v_motivo,
        updated_at = now()
    WHERE id = p_compra_id;

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
            'pago_id', v_pago_id,
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
        'pago_id', v_pago_id,
        'event_id', v_event_id,
        'estado', v_estado,
        'motivo', v_motivo
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.procesar_pago(UUID)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.procesar_pago(UUID)
TO service_role;

COMMIT;