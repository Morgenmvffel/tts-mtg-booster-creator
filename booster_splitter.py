import os
import json
import requests
import sys

def download_json_data(url):
    """Download JSON data from the specified URL."""
    print(f"Downloading data from {url}...")
    response = requests.get(url)
    response.raise_for_status()
    return response.json()

def add_sheet_order_to_boosters(data):
    """Add sheet order information to each booster in the data."""
    for obj in data:
        if 'boosters' in obj:
            for booster in obj['boosters']:
                # Extract and store the order of sheets
                booster['sheet_order'] = list(booster['sheets'].keys())

def save_json_to_file(data, file_path):
    """Save JSON data to a specified file."""
    with open(file_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
    print(f"Saved data to {file_path}")

def process_and_save_boosters(data, output_dir):
    """Process each booster and save it to individual JSON files."""
    index = []
    count = 0

    for obj in data:
        code = obj.get("code")
        name = obj.get("name")

        if not code or not name:
            print("Warning: Skipping entry without 'code' or 'name'")
            continue

        file_path = os.path.join(output_dir, f"{code}.json")
        save_json_to_file(obj, file_path)
        count += 1

        # Append booster information to index without filename
        index.append({
            "name": name,
            "code": code
        })

    return index, count

def main():
    # Constants for URLs and file paths
    GITHUB_URL = "https://raw.githubusercontent.com/taw/magic-sealed-data/refs/heads/master/sealed_basic_data.json"
    OUTPUT_DIR = "booster"
    FULL_JSON_FILE = "sealed_basic_data.json"
    INDEX_FILE = "booster_index.json"

    try:
        # Ensure the output directory exists
        os.makedirs(OUTPUT_DIR, exist_ok=True)

        # Download the JSON data from GitHub
        data = download_json_data(GITHUB_URL)

        # Add sheet order information to boosters
        add_sheet_order_to_boosters(data)

        # Save the full JSON data with added sheet order
        save_json_to_file(data, FULL_JSON_FILE)

        # Process boosters and save each to a separate file
        index, count = process_and_save_boosters(data, OUTPUT_DIR)

        # Write the booster index file
        save_json_to_file(index, INDEX_FILE)

        print(f"Generated index file: {INDEX_FILE}")
        print(f"Successfully processed {count} booster files.")

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
