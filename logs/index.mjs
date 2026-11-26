import { LambdaClient, InvokeCommand } from "@aws-sdk/client-lambda";
import { crearConsumer, TOPIC } from "../shared/kafka.mjs";

const GROUP_ID = "vetcare360-logs-group";

const consumer = crearConsumer(GROUP_ID);

const lambda = new LambdaClient({
  region: process.env.AWS_REGION || "us-east-1",
  maxAttempts: 2
});

const FUNCTION_NAME = process.env.LOGS_LAMBDA_NAME;

if (!FUNCTION_NAME) {
  throw new Error("LOGS_LAMBDA_NAME no configurado");
}

async function registrarLog(evento) {
  const response = await lambda.send(
    new InvokeCommand({
      FunctionName: FUNCTION_NAME,
      InvocationType: "RequestResponse",
      Payload: Buffer.from(JSON.stringify(evento))
    }),
    {
      abortSignal: AbortSignal.timeout(40000)
    }
  );

  const resultado = JSON.parse(
    Buffer.from(response.Payload || []).toString("utf8")
  );

  if (
    response.FunctionError ||
    response.StatusCode !== 200 ||
    resultado.success !== true
  ) {
    throw new Error("La Lambda no pudo registrar el evento");
  }

  return resultado;
}

async function iniciar() {
  await consumer.connect();

  await consumer.subscribe({
    topic: TOPIC,
    fromBeginning: true
  });

  console.log("Consumer de logs iniciado");
  console.log("Grupo:", GROUP_ID);
  console.log("Topic:", TOPIC);

  await consumer.run({
    eachMessage: async ({ topic, partition, message }) => {
      let evento;

      try {
        evento = JSON.parse(message.value.toString("utf8"));
      } catch {
        console.warn("JSON invalido omitido:", message.offset);
        return;
      }

      if (
        typeof evento?.event_id !== "string" ||
        !evento.event_id.trim() ||
        typeof evento.type !== "string" ||
        !evento.type.trim()
      ) {
        console.warn("Evento invalido omitido:", message.offset);
        return;
      }

      console.log("Evento recibido:", evento.event_id);

      const resultado = await registrarLog(evento);

      console.log(JSON.stringify({
        event_id: evento.event_id,
        topic,
        partition,
        offset: message.offset,
        registrado: resultado.success,
        duplicado: resultado.duplicate
      }));
    }
  });
}

async function detener() {
  await consumer.disconnect();
  lambda.destroy();
  process.exit(0);
}

process.once("SIGINT", detener);
process.once("SIGTERM", detener);

iniciar().catch(async error => {
  console.error("Error del consumer:", error.message);
  await consumer.disconnect().catch(() => {});
  lambda.destroy();
  process.exit(1);
});
