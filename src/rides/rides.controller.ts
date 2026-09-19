import {
  Body,
  Controller,
  Param,
  Patch,
  Post,
  UseGuards,
} from '@nestjs/common';
import {
  CurrentAccessToken,
  CurrentUser,
  CurrentUserPayload,
} from '../auth/current-user.decorator';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { RequestRideDto } from './dto/request-ride.dto';
import { RidesService } from './rides.service';

@Controller('api/rides')
export class RidesController {
  constructor(private readonly ridesService: RidesService) {}

  @Patch(':rideId/accept')
  @UseGuards(JwtAuthGuard)
  accept(
    @Param('rideId') rideId: string,
    @CurrentUser() user: CurrentUserPayload,
    @CurrentAccessToken() accessToken: string,
  ) {
    return this.ridesService.accept(rideId, user, accessToken);
  }

  @Patch(':rideId/start')
  @UseGuards(JwtAuthGuard)
  start(
    @Param('rideId') rideId: string,
    @CurrentUser() user: CurrentUserPayload,
    @CurrentAccessToken() accessToken: string,
  ) {
    return this.ridesService.start(rideId, user, accessToken);
  }

  @Patch(':rideId/complete')
  @UseGuards(JwtAuthGuard)
  complete(
    @Param('rideId') rideId: string,
    @CurrentUser() user: CurrentUserPayload,
    @CurrentAccessToken() accessToken: string,
  ) {
    return this.ridesService.complete(rideId, user, accessToken);
  }

  @Patch(':rideId/cancel')
  @UseGuards(JwtAuthGuard)
  cancel(
    @Param('rideId') rideId: string,
    @CurrentUser() user: CurrentUserPayload,
    @CurrentAccessToken() accessToken: string,
  ) {
    return this.ridesService.cancel(rideId, user, accessToken);
  }

  @Post('request')
  @UseGuards(JwtAuthGuard)
  request(
    @Body() dto: RequestRideDto,
    @CurrentUser() user: CurrentUserPayload,
    @CurrentAccessToken() accessToken: string,
  ) {
    return this.ridesService.request(dto, user, accessToken);
  }
}