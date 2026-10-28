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

-- Jeu de données de départ — 6 produits par famille (24 au total), de quoi
-- montrer les filtres par catégorie et un parcours de commande réaliste.
INSERT INTO products (name, category, price_cents, stock_qty, description, image_key) VALUES
  -- Bien-être et routines quotidiennes
  ('Magnésium marin',             'bien-etre', 1490, 120, 'Magnésium marin, 60 gélules, routine quotidienne.',          'products/bien-etre/1.jpg'),
  ('Multivitamines complètes',    'bien-etre', 1990, 80,  'Complexe de vitamines et minéraux, 1 comprimé/jour.',        'products/bien-etre/2.jpg'),
  ('Oméga-3 huile de poisson',    'bien-etre', 1790, 95,  'EPA/DHA concentrés, 90 capsules.',                           'products/bien-etre/3.jpg'),
  ('Probiotiques 10 milliards',   'bien-etre', 2290, 60,  'Flore intestinale, 30 gélules gastro-résistantes.',          'products/bien-etre/4.jpg'),
  ('Vitamine D3 + K2',            'bien-etre', 1290, 150, 'Gouttes, flacon 20ml, 300 doses.',                           'products/bien-etre/5.jpg'),
  ('Mélatonine sommeil',          'bien-etre', 990,  100, 'Favorise l''endormissement, 30 comprimés.',                  'products/bien-etre/6.jpg'),

  -- Nutrition sportive
  ('Créatine monohydrate',        'nutrition-sportive', 2490, 60, 'Créatine pure, 300g, pour la force et la récupération.', 'products/nutrition-sportive/1.jpg'),
  ('Whey protéine vanille',       'nutrition-sportive', 3490, 45, 'Whey isolate, 1kg, 25g de protéines par dose.',          'products/nutrition-sportive/2.jpg'),
  ('BCAA 2:1:1',                  'nutrition-sportive', 1990, 70, 'Acides aminés branchés, 400g, arôme fruits rouges.',     'products/nutrition-sportive/3.jpg'),
  ('Pre-workout energy',          'nutrition-sportive', 2690, 50, 'Caféine et beta-alanine, 300g, 30 doses.',               'products/nutrition-sportive/4.jpg'),
  ('Barres protéinées x12',       'nutrition-sportive', 1890, 90, 'Boîte de 12 barres, 20g de protéines chacune.',          'products/nutrition-sportive/5.jpg'),
  ('Shaker VITALORA 700ml',       'nutrition-sportive', 790,  200, 'Shaker avec grille de mélange.',                        'products/nutrition-sportive/6.jpg'),

  -- Compléments à base de plantes
  ('Gélules de curcuma bio',      'plantes', 1690, 70, 'Curcuma bio, 90 gélules, extrait standardisé.',       'products/plantes/1.jpg'),
  ('Teinture d''ashwagandha',     'plantes', 1890, 50, 'Teinture mère d''ashwagandha, flacon 50ml.',          'products/plantes/2.jpg'),
  ('Infusion détox bio',          'plantes', 990,  110, 'Mélange de plantes, 20 sachets.',                    'products/plantes/3.jpg'),
  ('Spiruline bio comprimés',     'plantes', 1590, 65, 'Spiruline bio, 200 comprimés.',                      'products/plantes/4.jpg'),
  ('Gélules de ginseng',          'plantes', 1790, 55, 'Ginseng rouge, 60 gélules, tonus et vitalité.',       'products/plantes/5.jpg'),
  ('Harpagophytum articulations', 'plantes', 1690, 60, 'Extrait de griffe du diable, 90 gélules.',            'products/plantes/6.jpg'),

  -- Beauté et nutrition
  ('Complexe peau-cheveux-ongles','beaute', 2190, 65, 'Biotine, zinc et collagène marin, 60 gélules.', 'products/beaute/1.jpg'),
  ('Collagène marin en poudre',   'beaute', 2990, 40, 'Collagène hydrolysé, 200g, arôme neutre.',      'products/beaute/2.jpg'),
  ('Acide hyaluronique',          'beaute', 2390, 45, 'Hydratation de la peau, 30 gélules.',           'products/beaute/3.jpg'),
  ('Vitamine C liposomale',       'beaute', 1890, 75, 'Antioxydant, biodisponibilité renforcée, 60 gélules.', 'products/beaute/4.jpg'),
  ('Zinc + biotine',              'beaute', 1290, 100, 'Soutien peau et cheveux, 90 comprimés.',        'products/beaute/5.jpg'),
  ('Huile de bourrache bio',      'beaute', 1590, 80, 'Peau et équilibre hormonal, 90 capsules.',       'products/beaute/6.jpg');
