export function esEventoCompraValido(evento, tipoEsperado) {
    return (
        evento !== null &&
        typeof evento === "object" &&
        evento.type === tipoEsperado &&
        typeof evento.event_id === "string" &&
        evento.event_id.trim().length > 0 &&
        typeof evento.compra_id === "string" &&
        /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(evento.compra_id) &&
        evento.simulacion === true
    );
}
