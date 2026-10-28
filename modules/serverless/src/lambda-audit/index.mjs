import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, PutCommand } from "@aws-sdk/lib-dynamodb";

const client = new DynamoDBClient({});
const docClient = DynamoDBDocumentClient.from(client);

const TABLE_NAME = process.env.TABLE_NAME;

export const handler = async (event) => {
    console.log("Événement SQS reçu (Audit) :", JSON.stringify(event, null, 2));

    for (const record of event.Records) {
        try {
            // 1. Extraire le message SQS
            const sqsBody = JSON.parse(record.body);
            
            // 2. Extraire le message SNS (contenu dans SQS Message)
            const order = JSON.parse(sqsBody.Message);

            console.log(`Traitement de la commande d'audit : ${order.order_id}`);

            // 3. Parcourir les articles pour les insérer dans DynamoDB (Single-Table design)
            for (const item of order.items) {
                const putParams = {
                    TableName: TABLE_NAME,
                    Item: {
                        PK: `ORDER#${order.order_id}`,
                        SK: `ITEM#${item.product_id}`,
                        customer_email: order.customer_email,
                        status: order.status || "confirmed",
                        category: item.category || "General",
                        qty: item.qty,
                        unit_price_cents: item.unit_price_cents,
                        created_at: order.created_at || new Date().toISOString()
                    }
                };

                await docClient.send(new PutCommand(putParams));
                console.log(`Article ${item.product_id} enregistré pour la commande ${order.order_id}`);
            }
        } catch (error) {
            console.error("Erreur lors du traitement du message d'audit :", error);
            throw error; // Fait remonter l'erreur pour que SQS gère la DLQ si besoin
        }
    }
    return { status: "SUCCESS" };
};