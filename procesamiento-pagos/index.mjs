import { esEventoCompraValido } from "../shared/eventos.mjs";
import { crearConsumer, TOPIC } from "../shared/kafka.mjs";
import { supabase } from "../shared/supabase.mjs";

const GROUP_ID = "vetcare360-pagos-group";
const consumer = crearConsumer(GROUP_ID);

async function iniciar() {
    await consumer.connect();

    await consumer.subscribe({
        topic: TOPIC,
        fromBeginning: true
    });

    console.log("Consumer de procesamiento de pagos iniciado");
    console.log("Grupo:", GROUP_ID);
    console.log("Topic:", TOPIC);

    await consumer.run({
        eachMessage: async ({ topic, partition, message }) => {
            let evento;

            try {
                evento = JSON.parse(message.value.toString("utf8"));
            } catch {
                console.warn("JSON invalido:", message.offset);
                return;
            }

            if (evento?.type !== "compra.validada") {
                return;
            }

            if (!esEventoCompraValido(evento, "compra.validada")) {
                console.warn("Evento de pago invalido:", message.offset);
                return;
            }

            console.log("Procesando pago simulado:", evento.compra_id);

            const { data, error } = await supabase
                .rpc("procesar_pago", {
                    p_compra_id: evento.compra_id
                })
                .abortSignal(AbortSignal.timeout(20000));

            if (error) {
                throw new Error(error.message);
            }

            if (data?.success !== true) {
                throw new Error("No se pudo procesar el pago");
            }

            console.log(JSON.stringify({
                event_id: evento.event_id,
                compra_id: evento.compra_id,
                pago_id: data.pago_id ?? null,
                topic,
                partition,
                offset: message.offset,
                estado: data.estado,
                duplicado: data.duplicate,
                motivo: data.motivo ?? null,
                simulacion: true
            }));
        }
    });
}

async function detener() {
    await consumer.disconnect();
    process.exit(0);
}

process.once("SIGINT", detener);
process.once("SIGTERM", detener);

iniciar().catch(async error => {
    console.error("Error del consumer:", error.message);
    await consumer.disconnect().catch(() => {});
    process.exit(1);
});
