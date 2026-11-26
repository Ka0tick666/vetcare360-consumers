import test from "node:test";
import assert from "node:assert/strict";
import { esEventoCompraValido } from "../shared/eventos.mjs";

const evento = {
    event_id: "evento-test-001",
    type: "compra.creada",
    compra_id: "00000000-0000-4000-8000-000000000001",
    simulacion: true
};

test("Acepta una compra creada valida", () => {
    assert.equal(esEventoCompraValido(evento, "compra.creada"), true);
});

test("Acepta una compra validada", () => {
    assert.equal(esEventoCompraValido({
        ...evento,
        type: "compra.validada"
    }, "compra.validada"), true);
});

test("Rechaza un tipo incorrecto", () => {
    assert.equal(esEventoCompraValido(evento, "compra.validada"), false);
});

test("Rechaza un evento sin identificador", () => {
    assert.equal(esEventoCompraValido({
        ...evento,
        event_id: ""
    }, "compra.creada"), false);
});

test("Rechaza un UUID incorrecto", () => {
    assert.equal(esEventoCompraValido({
        ...evento,
        compra_id: "incorrecto"
    }, "compra.creada"), false);
});

test("Rechaza pagos no simulados", () => {
    assert.equal(esEventoCompraValido({
        ...evento,
        simulacion: false
    }, "compra.creada"), false);
});

test("Rechaza eventos nulos", () => {
    assert.equal(esEventoCompraValido(null, "compra.creada"), false);
});

test("Rechaza eventos sin datos", () => {
    assert.equal(esEventoCompraValido({}, "compra.creada"), false);
});

test("Rechaza eventos sin indicador de simulacion", () => {
    const { simulacion, ...incompleto } = evento;
    assert.equal(esEventoCompraValido(incompleto, "compra.creada"), false);
});

test("Rechaza identificadores vacios con espacios", () => {
    assert.equal(esEventoCompraValido({
        ...evento,
        event_id: "   "
    }, "compra.creada"), false);
});
