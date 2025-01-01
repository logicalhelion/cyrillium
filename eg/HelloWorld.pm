use v5.38;
use Cyrillium::App;

package HelloWorld {
    use parent 'Cyrillium::App';

    sub ROUTES {
        return {
            '/' => { 'GET' => 'hello_world' },
        }
    }

    sub hello_world {
        return [
            '200 OK',
            [ -type => 'text/html; charset=utf-8', ],
            '<h1>Hello World!</h1>',
        ];
    }
}
1;
__END__

