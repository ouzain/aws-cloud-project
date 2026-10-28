export const handler = async (event) => {
    console.log("Événement SQS reçu (Logistique) :", JSON.stringify(event, null, 2));

    for (const record of event.Records) {
        try {
            const sqsBody = JSON.parse(record.body);
            const order = JSON.parse(sqsBody.Message);

            console.log(`[LOGISTIQUE] Réception de la commande ${order.order_id} pour ${order.customer_email}`);
            console.log(`[EMBALLAGE] Préparation de ${order.items.length} type(s) de produit(s)...`);

            for (const item of order.items) {
                console.log(` -> Colisage : ${item.qty}x [${item.product_id}]`);
            }

            console.log(`[EXPÉDITION] Colis remis au transporteur. Statut final : shipped 🚀`);
        } catch (error) {
            console.error("Erreur logistique :", error);
            throw error;
        }
    }
    return { status: "SUCCESS" };
};