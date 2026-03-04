-- migrate:up
ALTER TABLE orders ADD CONSTRAINT orders_user_id_fk FOREIGN KEY (user_id) REFERENCES users (id);

-- migrate:down
ALTER TABLE orders DROP FOREIGN KEY orders_user_id_fk;
