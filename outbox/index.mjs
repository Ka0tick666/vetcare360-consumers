import { kafka, TOPIC } from "../shared/kafka.mjs";
import { supabase } from "../shared/supabase.mjs";
import { setTimeout as esperar } from "node:timers/promises";

const producer = kafka.producer({
    allowAutoTopicCreation: false,
    idempotent: true,
    maxInFlightRequests: 1
});

const INTERVALO = Number(
    process.env.OUTBOX_POLL_INTERVAL_MS || 3000
);

const BATCH_SIZE = Number(
    process.env.OUTBOX_BATCH_SIZE || 20
);

let ejecutando = true;

async function publicarPendientes() {
    const { data: eventos, error } = await supabase
        .from("compra_eventos_outbox")
        .select("*")
        .eq("publicado", false)
        .order("created_at", { ascending: true })
        .order("event_id", { ascending: true })
        .limit(BATCH_SIZE);

    if (error) {
        throw new Error(error.message);
    }

    for (const evento of eventos) {
        if (!ejecutando) break;

        try {
            await producer.send({
                topic: TOPIC,
                acks: -1,
                messages: [
                    {
                        key: evento.compra_id,
                        value: JSON.stringify(evento.payload)
                    }
                ]
            });

            const { error: errorUpdate } = await supabase
                .from("compra_eventos_outbox")
                .update({
                    publicado: true,
                    publicado_at: new Date().toISOString(),
                    intentos: evento.intentos + 1,
                    ultimo_error: null
                })
                .eq("event_id", evento.event_id)
                .eq("publicado", false);

            if (errorUpdate) {
                throw new Error(errorUpdate.message);
            }

            console.log(JSON.stringify({
                event_id: evento.event_id,
                compra_id: evento.compra_id,
                tipo: evento.tipo,
                publicado: true
            }));

        } catch (error) {
            console.error(
                "Error publicando evento:",
                evento.event_id,
                error.message
            );

            const { error: errorRegistro } = await supabase
                .from("compra_eventos_outbox")
                .update({
                    intentos: evento.intentos + 1,
                    ultimo_error: error.message.slice(0, 500)
                })
                .eq("event_id", evento.event_id)
                .eq("publicado", false);

            if (errorRegistro) {
                console.error(
                    "No se pudo registrar el intento:",
                    errorRegistro.message
                );
            }

            break;
        }
    }
}

async function iniciar() {
    await producer.connect();

    console.log("Publicador outbox iniciado");
    console.log("Topic:", TOPIC);
    console.log("Intervalo:", INTERVALO);
    console.log("Batch:", BATCH_SIZE);

    while (ejecutando) {
        try {
            await publicarPendientes();
        } catch (error) {
            console.error("Error en outbox:", error.message);
        }

        if (ejecutando) {
            await esperar(INTERVALO);
        }
    }
}

process.once("SIGINT", () => {
    ejecutando = false;
});

process.once("SIGTERM", () => {
    ejecutando = false;
});

iniciar()
    .catch(error => {
        console.error("Error fatal:", error.message);
        process.exitCode = 1;
    })
    .finally(async () => {
        await producer.disconnect();
    });
