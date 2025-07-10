import os
import json
import requests
import sys

def main():
    GITHUB_URL = "https://raw.githubusercontent.com/taw/magic-sealed-data/refs/heads/master/sealed_basic_data.json"
    
    OUTPUT_DIR = "booster"
    FULL_JSON_FILE = "sealed_basic_data.json"
    INDEX_FILE = "booster_index.json"

    try:
        # Create output directory if it doesn't exist
        os.makedirs(OUTPUT_DIR, exist_ok=True)

        # Download the JSON
        print(f"Downloading data from {GITHUB_URL}...")
        response = requests.get(GITHUB_URL)
        response.raise_for_status()

        data = response.json()

        # Save full JSON
        with open(FULL_JSON_FILE, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
        print(f"Saved full dataset to {FULL_JSON_FILE}")

        index = []
        count = 0

        # Split and save each object
        for obj in data:
            code = obj.get("code")
            name = obj.get("name")

            if not code or not name:
                print("Warning: Skipping entry without 'code' or 'name'")
                continue

            file_path = os.path.join(OUTPUT_DIR, f"{code}.json")
            with open(file_path, "w", encoding="utf-8") as f:
                json.dump(obj, f, indent=2)
            count += 1

            index.append({
                "name": name,
                "code": code,
                "filename": f"{OUTPUT_DIR}/{code}.json"
            })

        # Write the booster index
        with open(INDEX_FILE, "w", encoding="utf-8") as f:
            json.dump(index, f, indent=2)
        print(f"Generated index file: {INDEX_FILE}")

        print(f"Successfully processed {count} booster files.")

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
