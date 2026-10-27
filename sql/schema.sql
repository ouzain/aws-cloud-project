-- VITALORA — schéma catalogue + commandes (Phase 2 / Phase 3 du roadmap)
-- À appliquer manuellement une fois la base déployée (voir README, section
-- "Charger le schéma") :
--   mysql -h <db_endpoint> -P 3306 -u vitalora_admin -p vitalora < sql/schema.sql

CREATE TABLE IF NOT EXISTS products (
  product_id   INT AUTO_INCREMENT PRIMARY KEY,
  name         VARCHAR(255)   NOT NULL,
  category     VARCHAR(64)    NOT NULL, -- bien-etre | nutrition-sportive | plantes | beaute
  price_cents  INT            NOT NULL,
  stock_qty    INT            NOT NULL DEFAULT 0,
  description  TEXT,
  image_key    VARCHAR(255),            -- ex: products/nutrition-sportive/1.jpg
  created_at   TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS orders (
  order_id       INT AUTO_INCREMENT PRIMARY KEY,
  customer_email VARCHAR(255) NOT NULL,
  status         VARCHAR(32)  NOT NULL DEFAULT 'received', -- received -> confirmed -> processing -> shipped
  created_at     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS order_items (
  order_id          INT NOT NULL,
  product_id        INT NOT NULL,
  qty               INT NOT NULL,
  unit_price_cents  INT NOT NULL,
  PRIMARY KEY (order_id, product_id),
  FOREIGN KEY (order_id) REFERENCES orders(order_id),
  FOREIGN KEY (product_id) REFERENCES products(product_id)
);

-- Jeu de données de départ — quelques produits par famille
INSERT INTO products (name, category, price_cents, stock_qty, description, image_key) VALUES
  ('Magnésium marin',        'bien-etre',          1490, 120, 'Magnésium marin, 60 gélules, routine quotidienne.',            'products/bien-etre/1.jpg'),
  ('Multivitamines complètes','bien-etre',          1990, 80,  'Complexe de vitamines et minéraux, 1 comprimé/jour.',          'products/bien-etre/2.jpg'),
  ('Créatine monohydrate',   'nutrition-sportive', 2490, 60,  'Créatine pure, 300g, pour la force et la récupération.',        'products/nutrition-sportive/1.jpg'),
  ('Whey protéine vanille',  'nutrition-sportive', 3490, 45,  'Whey isolate, 1kg, 25g de protéines par dose.',                 'products/nutrition-sportive/2.jpg'),
  ('Gélules de curcuma bio', 'plantes',            1690, 70,  'Curcuma bio, 90 gélules, extrait standardisé.',                'products/plantes/1.jpg'),
  ('Teinture d''ashwagandha','plantes',            1890, 50,  'Teinture mère d''ashwagandha, flacon 50ml.',                   'products/plantes/2.jpg'),
  ('Complexe peau-cheveux-ongles', 'beaute',        2190, 65,  'Biotine, zinc et collagène marin, 60 gélules.',                'products/beaute/1.jpg'),
  ('Collagène marin en poudre', 'beaute',           2990, 40,  'Collagène hydrolysé, 200g, arôme neutre.',                     'products/beaute/2.jpg');
