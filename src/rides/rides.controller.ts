import { Body, Controller, Post, UseGuards } from '@nestjs/common';
import { CurrentUser, CurrentUserPayload } from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { RequestRideDto } from './dto/request-ride.dto';
import { RidesService } from './rides.service';

@Controller('api/rides')
export class RidesController {
  constructor(private readonly ridesService: RidesService) {}

  @Post('request')
  @UseGuards(JwtAuthGuard)
  request(
    @Body() dto: RequestRideDto,
    @CurrentUser() user: CurrentUserPayload,
  ) {
    return this.ridesService.request(dto, user);
  }
}