import "dotenv/config";
import { Kafka, logLevel } from "kafkajs";

const brokers = process.env.KAFKA_BROKERS
  ?.split(",")
  .map(broker => broker.trim())
  .filter(Boolean);

if (!brokers?.length) {
  throw new Error("KAFKA_BROKERS no configurado");
}

export const kafka = new Kafka({
  clientId: process.env.KAFKA_CLIENT_ID || "vetcare360-consumers",
  brokers,
  logLevel: logLevel.INFO,
  connectionTimeout: 10000,
  requestTimeout: 30000,
  retry: {
    initialRetryTime: 300,
    retries: 8
  }
});

export const TOPIC = process.env.KAFKA_TOPIC || "compras";

export function crearConsumer(groupId) {
  return kafka.consumer({
    groupId,
    sessionTimeout: 60000,
    heartbeatInterval: 3000,
    allowAutoTopicCreation: false
  });
}
