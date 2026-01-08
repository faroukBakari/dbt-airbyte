-- ============================================================
-- Optional: Seed test data to simulate Airbyte Sample Data output
-- Run this CONNECTED TO airbyte_raw database
-- Mimics the Airbyte "Sample Data (Faker)" connector schema
-- IDEMPOTENT: Safe to run multiple times
-- ============================================================

-- Create mock Airbyte raw tables (matching Sample Data connector output)
CREATE TABLE IF NOT EXISTS _airbyte_raw_users (
    _airbyte_raw_id VARCHAR(36) DEFAULT gen_random_uuid()::varchar,
    _airbyte_data JSONB NOT NULL,
    _airbyte_extracted_at TIMESTAMPTZ DEFAULT NOW(),
    _airbyte_loaded_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS _airbyte_raw_products (
    _airbyte_raw_id VARCHAR(36) DEFAULT gen_random_uuid()::varchar,
    _airbyte_data JSONB NOT NULL,
    _airbyte_extracted_at TIMESTAMPTZ DEFAULT NOW(),
    _airbyte_loaded_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS _airbyte_raw_purchases (
    _airbyte_raw_id VARCHAR(36) DEFAULT gen_random_uuid()::varchar,
    _airbyte_data JSONB NOT NULL,
    _airbyte_extracted_at TIMESTAMPTZ DEFAULT NOW(),
    _airbyte_loaded_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert sample users ONLY if table is empty (idempotent)
INSERT INTO _airbyte_raw_users (_airbyte_data)
SELECT * FROM (VALUES
    ('{"id": 1, "name": "Alice Johnson", "email": "alice.johnson@example.com", "gender": "Female", "title": "Ms.", "occupation": "Software Engineer", "nationality": "American", "language": "English", "academic_degree": "Master", "age": 32, "blood_type": "A+", "address": {"city": "San Francisco", "state": "California", "country_code": "US", "postal_code": "94102", "street_name": "Market St", "street_number": "123"}, "created_at": "2024-01-15T10:00:00Z", "updated_at": "2024-06-01T08:30:00Z"}'::jsonb),
    ('{"id": 2, "name": "Bob Smith", "email": "bob.smith@example.com", "gender": "Male", "title": "Mr.", "occupation": "Data Analyst", "nationality": "Canadian", "language": "English", "academic_degree": "Bachelor", "age": 28, "blood_type": "O+", "address": {"city": "Toronto", "state": "Ontario", "country_code": "CA", "postal_code": "M5V 3A8", "street_name": "King St", "street_number": "456"}, "created_at": "2024-02-20T14:30:00Z", "updated_at": "2024-05-15T12:00:00Z"}'::jsonb),
    ('{"id": 3, "name": "Charlie Brown", "email": "charlie.brown@example.com", "gender": "Male", "title": "Dr.", "occupation": "Product Manager", "nationality": "British", "language": "English", "academic_degree": "PhD", "age": 45, "blood_type": "B-", "address": {"city": "London", "state": "England", "country_code": "GB", "postal_code": "EC1A 1BB", "street_name": "Oxford St", "street_number": "789"}, "created_at": "2024-03-10T09:15:00Z", "updated_at": "2024-04-20T16:45:00Z"}'::jsonb)
) AS v(data)
WHERE NOT EXISTS (SELECT 1 FROM _airbyte_raw_users LIMIT 1);

-- Insert sample products ONLY if table is empty (idempotent)
INSERT INTO _airbyte_raw_products (_airbyte_data)
SELECT * FROM (VALUES
    ('{"id": 101, "make": "Tesla", "model": "Model 3", "year": 2024, "price": 42990.00, "created_at": "2024-01-01T00:00:00Z"}'::jsonb),
    ('{"id": 102, "make": "Toyota", "model": "Camry", "year": 2023, "price": 28500.00, "created_at": "2024-01-01T00:00:00Z"}'::jsonb),
    ('{"id": 103, "make": "Honda", "model": "Civic", "year": 2024, "price": 25800.00, "created_at": "2024-01-01T00:00:00Z"}'::jsonb),
    ('{"id": 104, "make": "BMW", "model": "X5", "year": 2023, "price": 65900.00, "created_at": "2024-01-01T00:00:00Z"}'::jsonb)
) AS v(data)
WHERE NOT EXISTS (SELECT 1 FROM _airbyte_raw_products LIMIT 1);

-- Insert sample purchases ONLY if table is empty (idempotent)
INSERT INTO _airbyte_raw_purchases (_airbyte_data)
SELECT * FROM (VALUES
    ('{"id": 1001, "user_id": 1, "product_id": 101, "purchased_at": "2024-04-01T14:30:00Z", "added_to_cart_at": "2024-03-28T10:00:00Z", "returned_at": null}'::jsonb),
    ('{"id": 1002, "user_id": 1, "product_id": 103, "purchased_at": "2024-05-15T09:45:00Z", "added_to_cart_at": "2024-05-14T16:20:00Z", "returned_at": null}'::jsonb),
    ('{"id": 1003, "user_id": 2, "product_id": 102, "purchased_at": "2024-05-01T11:00:00Z", "added_to_cart_at": "2024-04-30T18:30:00Z", "returned_at": null}'::jsonb),
    ('{"id": 1004, "user_id": 3, "product_id": 104, "purchased_at": "2024-05-10T15:20:00Z", "added_to_cart_at": "2024-05-08T12:00:00Z", "returned_at": "2024-05-20T10:00:00Z"}'::jsonb)
) AS v(data)
WHERE NOT EXISTS (SELECT 1 FROM _airbyte_raw_purchases LIMIT 1);

SELECT 'Test data seeded successfully! (Mimics Airbyte Sample Data connector)' AS status;
