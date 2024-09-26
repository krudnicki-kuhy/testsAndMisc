import requests 
import json 
import os
from pathlib import Path

requests_send = 0
while requests_send < 90:
    res = requests.get('https://api.thecatapi.com/v1/images/search?limit=100&api_key=')
    requests_send += 1
    response = json.loads(res.text)
    urls = []
    for cat in response: 
        urls.append(cat.get("url"))

    Path("./CATS2").mkdir(parents=True, exist_ok=True)
    for url in urls:
        try:
            # Get the image content
            response = requests.get(url)
            response.raise_for_status()  # Raise an exception for HTTP errors

            # Extract the image name from the URL
            image_name = os.path.basename(url)
            image_path = os.path.join("./CATS2/", image_name)

            # Save the image to the directory
            with open(image_path, 'wb') as file:
                file.write(response.content)

            print(f"Saved {url} as {image_path}")

        except requests.exceptions.RequestException as e:
            print(f"Failed to download {url}: {e}")
