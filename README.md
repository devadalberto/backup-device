# backup-device
python (django) project to copy (and manage) media files from any device (mobiles, usb-drives) etc...

## Environment variables

The project uses [`python-dotenv`](https://pypi.org/project/python-dotenv/) to load environment variables from a `.env` file. The following line is included near the top of the main entry points:

```python
from dotenv import load_dotenv; load_dotenv()
```

This code is present in `manage.py`, `config/wsgi.py`, and `config/asgi.py`. Ensure a `.env` file exists before starting the application so that these environment variables are available.
