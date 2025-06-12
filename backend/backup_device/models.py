from django.db import models


class Device(models.Model):
    """Simple device representation."""

    name = models.CharField(max_length=100)
    created = models.DateTimeField(auto_now_add=True)

    def __str__(self) -> str:  # pragma: no cover - simple representation
        return self.name
