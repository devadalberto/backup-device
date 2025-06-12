from typing import List

from backup_device.models import Device
from django.shortcuts import get_object_or_404
from media_lake.models import MediaFile
from ninja import File, ModelSchema, NinjaAPI
from ninja.files import UploadedFile


class DeviceSchema(ModelSchema):
    class Config:
        model = Device
        model_fields = ["id", "name", "created"]


class DeviceCreateSchema(ModelSchema):
    class Config:
        model = Device
        model_fields = ["name"]


class MediaFileSchema(ModelSchema):
    class Config:
        model = MediaFile
        model_fields = ["id", "device_id", "file", "uploaded"]


api = NinjaAPI()


@api.get("/devices/", response=List[DeviceSchema])
def list_devices(request):
    return Device.objects.all()


@api.post("/devices/", response=DeviceSchema)
def create_device(request, payload: DeviceCreateSchema):
    device = Device.objects.create(**payload.dict())
    return device


@api.get("/media/", response=List[MediaFileSchema])
def list_media(request):
    return MediaFile.objects.all()


@api.post("/media/", response=MediaFileSchema)
def upload_media(request, device_id: int, file: UploadedFile = File(...)):
    device = get_object_or_404(Device, id=device_id)
    media = MediaFile.objects.create(device=device, file=file)
    return media
