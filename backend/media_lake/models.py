from backup_device.models import Device
from django.db import models


class MediaFile(models.Model):
    """File stored in the media lake."""

    device = models.ForeignKey(
        Device, on_delete=models.CASCADE, related_name="media_files"
    )
    file = models.FileField(upload_to="uploads/")
    uploaded = models.DateTimeField(auto_now_add=True)

    def __str__(self) -> str:  # pragma: no cover - simple representation
        return self.file.name
