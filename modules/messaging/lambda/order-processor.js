// VITALORA — consommateur de la file SQS order-processing (Phase 4).
// Pour chaque commande, exécute, trace dans CloudWatch Logs ET notifie par SNS
// (topic order-notifications, abonné e-mail), DANS L'ORDRE :
//   1. CUSTOMER_CONFIRMATION   confirmation client
//   2. INTERNAL_NOTIFICATION   notification interne (équipe logistique)
//   3. PROCESSING_SIMULATION   simulation du traitement (emballage/expédition)
// Une exception sur un message le renvoie en file (puis en DLQ après 3 essais) ;
// en cas de nouvel essai, les notifications déjà envoyées peuvent être rejouées.

// Le SDK v3 est fourni par le runtime nodejs20.x
const { SNSClient, PublishCommand } = require("@aws-sdk/client-sns");

const sns = new SNSClient({});
const NOTIFICATION_TOPIC_ARN = process.env.NOTIFICATION_TOPIC_ARN;

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function log(step, stepName, order, extra = {}) {
  console.log(
    JSON.stringify({
      event: "order_pipeline",
      step,
      stepName,
      orderId: order.order_id,
      ...extra,
    })
  );
}

// Sujet SNS : ASCII uniquement, 100 caractères max.
async function notify(step, order, subject, message) {
  if (!NOTIFICATION_TOPIC_ARN) return;
  await sns.send(
    new PublishCommand({
      TopicArn: NOTIFICATION_TOPIC_ARN,
      Subject: `[VITALORA] Commande #${order.order_id} - ${step}/3 ${subject}`,
      Message: message,
    })
  );
}

async function processOrder(order) {
  const totalEur = ((order.total_cents || 0) / 100).toFixed(2);
  const lines = (order.items || []).map((it) => `- produit ${it.product_id} x ${it.qty}`).join("\n");

  const confirmation = `Confirmation de commande #${order.order_id} envoyée à ${order.customer_email} (total ${totalEur} EUR)`;
  log(1, "CUSTOMER_CONFIRMATION", order, { to: order.customer_email, message: confirmation });
  await notify(1, order, "Confirmation client", `${confirmation}\n\n${lines}`);

  const internal = `Nouvelle commande #${order.order_id} à préparer : ${(order.items || []).length} ligne(s)`;
  log(2, "INTERNAL_NOTIFICATION", order, { message: internal });
  await notify(2, order, "Notification interne", `${internal}\n\n${lines}`);

  log(3, "PROCESSING_SIMULATION", order, { message: "Préparation en cours" });
  await sleep(1500);
  const done = `Commande #${order.order_id} traitée (statut simulé : shipped)`;
  log(3, "PROCESSING_SIMULATION", order, { message: done, status: "shipped" });
  await notify(3, order, "Traitement termine", done);
}

exports.handler = async (event) => {
  const batchItemFailures = [];

  for (const record of event.Records) {
    try {
      await processOrder(JSON.parse(record.body));
    } catch (err) {
      console.error(
        JSON.stringify({ event: "order_pipeline_error", messageId: record.messageId, error: err.message })
      );
      batchItemFailures.push({ itemIdentifier: record.messageId });
    }
  }

  return { batchItemFailures };
};
