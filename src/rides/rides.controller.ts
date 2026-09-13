import { Body, Controller, Post } from '@nestjs/common';
import { RequestRideDto } from './dto/request-ride.dto';
import { RidesService } from './rides.service';

@Controller('api/rides')
export class RidesController {
  constructor(private readonly ridesService: RidesService) {}

  @Post('request')
  request(@Body() dto: RequestRideDto) {
    return this.ridesService.request(dto);
  }
}
