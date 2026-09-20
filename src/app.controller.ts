import { Controller, Get } from '@nestjs/common';

@Controller('api')
export class AppController {
  @Get('health')
  health(): { status: string } {
    return {
      status: 'ok',
    };
  }
}
